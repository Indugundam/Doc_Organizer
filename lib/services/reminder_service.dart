import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../utils/format_date.dart';
import 'storage_service.dart';

/// What happens to a document on its reminder date.
enum ReminderKind {
  expiry('Expires', 'expires'),
  renewal('Renewal due', 'is due for renewal');

  const ReminderKind(this.label, this.verb);

  /// Shown before the date, e.g. "Expires 3/1/2027".
  final String label;

  /// Used in notifications, e.g. "Passport expires in 1 week".
  final String verb;
}

/// How long before the date the advance notification is sent.
enum ReminderLead {
  onTheDay(0, 'On the day only', ''),
  oneDay(1, '1 day before', 'tomorrow'),
  oneWeek(7, '1 week before', 'in 1 week'),
  twoWeeks(14, '2 weeks before', 'in 2 weeks'),
  oneMonth(30, '30 days before', 'in 30 days'),
  threeMonths(90, '90 days before', 'in 90 days');

  const ReminderLead(this.days, this.label, this.relative);

  final int days;
  final String label;

  /// Completes "`document` expires …".
  final String relative;

  static ReminderLead fromDays(int days) => values.firstWhere(
    (l) => l.days == days,
    orElse: () => ReminderLead.oneWeek,
  );
}

class DocumentReminder {
  const DocumentReminder({
    required this.id,
    required this.date,
    required this.kind,
    required this.lead,
  });

  /// Stable number the reminder's notifications are scheduled under.
  final int id;

  /// The expiry/renewal day (midnight local time).
  final DateTime date;
  final ReminderKind kind;
  final ReminderLead lead;

  bool get isPast => !date.isAfter(ReminderService.today());

  /// Whole days from today until [date]; negative once it has passed.
  int get daysLeft => date.difference(ReminderService.today()).inDays;

  /// e.g. "Expires 3/1/2027" or "Expired 3/1/2025".
  String get summary => isPast && kind == ReminderKind.expiry
      ? 'Expired ${formatDate(date)}'
      : '${kind.label} ${formatDate(date)}';

  Map<String, dynamic> toJson() => {
    'i': id,
    'd': _dateKey(date),
    'k': kind.name,
    'l': lead.days,
  };

  factory DocumentReminder.fromJson(Map<String, dynamic> json) =>
      DocumentReminder(
        id: json['i'] as int,
        date: DateTime.parse(json['d'] as String),
        kind: ReminderKind.values.firstWhere(
          (k) => k.name == json['k'],
          orElse: () => ReminderKind.expiry,
        ),
        lead: ReminderLead.fromDays(json['l'] as int),
      );

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Expiry/renewal reminders on documents (insurance, warranty, passport…),
/// delivered as local notifications - nothing leaves the device.
///
/// Each reminder gets a notification on the day itself and, optionally, one
/// [ReminderLead] days before, both at [notifyHour]. Reminders are stored in
/// app support storage keyed by path relative to the DocManager root (like
/// [SearchIndex]) and follow their document through renames and moves.
class ReminderService {
  ReminderService._();

  /// Local time of day notifications are delivered.
  static const notifyHour = 9;

  /// Bumped whenever a reminder is added, changed or removed.
  static final revision = ValueNotifier<int>(0);

  /// Called with the document whose notification was tapped.
  static void Function(File file)? onOpenDocument;

  static final _plugin = FlutterLocalNotificationsPlugin();
  static final _reminders = <String, DocumentReminder>{};
  static var _nextId = 1;
  static File? _launchedFrom;
  static Future<void>? _ready;

  /// iOS keeps at most 64 pending notifications per app; each reminder uses
  /// two, so only the soonest are scheduled and the rest follow on later
  /// launches as earlier ones pass.
  static const _maxScheduled = 30;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'document_reminders',
      'Document reminders',
      channelDescription: 'Expiry and renewal dates set on documents',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  static DateTime today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// When the notification for [lead] fires for a reminder on [date].
  static DateTime notifyTime(DateTime date, ReminderLead lead) =>
      DateTime(date.year, date.month, date.day - lead.days, notifyHour);

  /// Whether [lead] would still notify for [date], i.e. its time is ahead.
  static bool leadAvailable(DateTime date, ReminderLead lead) =>
      notifyTime(date, lead).isAfter(DateTime.now());

  static Future<void> init() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _nextId = json['next'] as int? ?? 1;
        final items = json['items'] as Map<String, dynamic>? ?? {};
        for (final e in items.entries) {
          _reminders[e.key] = DocumentReminder.fromJson(
            e.value as Map<String, dynamic>,
          );
        }
      }
    } catch (_) {
      // A corrupt file loses the reminders rather than the app.
    }
    revision.value++;
    // Not awaited: platform setup and re-scheduling run in the background.
    _ready = _setUp();
  }

  static Future<void> _setUp() async {
    try {
      tz.initializeTimeZones();
      try {
        final local = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(local.identifier));
      } catch (_) {
        // Unknown zone: fall back to the package default (UTC).
      }
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_notification'),
          // Permission is asked the first time a reminder is set instead.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) => _open(r.payload),
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _launchedFrom = await _fileFor(launch!.notificationResponse?.payload);
        openLaunchedDocument();
      }
      await _pruneMissing();
      await _rescheduleAll();
    } catch (e) {
      debugPrint('Reminder setup failed: $e');
    }
  }

  /// Opens the document whose notification launched the app, once
  /// [onOpenDocument] is ready to show it.
  static void openLaunchedDocument() {
    final file = _launchedFrom;
    final open = onOpenDocument;
    if (file == null || open == null) return;
    _launchedFrom = null;
    open(file);
  }

  static Future<void> _open(String? payload) async {
    final file = await _fileFor(payload);
    if (file != null) onOpenDocument?.call(file);
  }

  static Future<File?> _fileFor(String? key) async {
    if (key == null) return null;
    final file = File(_absolute(await StorageService.rootDir(), key));
    return await file.exists() ? file : null;
  }

  /// The reminder set on [file], if any. Synchronous so list rows can show
  /// it; null until the DocManager root has been resolved.
  static DocumentReminder? reminderFor(File file) {
    final root = StorageService.cachedRootDir;
    if (root == null) return null;
    return _reminders[_relative(root, file.path)];
  }

  /// Every reminder with its document, soonest first.
  static Future<List<(File, DocumentReminder)>> all() async {
    final root = await StorageService.rootDir();
    final list = [
      for (final e in _reminders.entries)
        (File(_absolute(root, e.key)), e.value),
    ]..sort((a, b) => a.$2.date.compareTo(b.$2.date));
    return list;
  }

  /// Sets (or replaces) the reminder on [file]. [date] must be after today.
  /// Returns false if notifications are turned off for the app, in which
  /// case the reminder is still saved but won't alert.
  static Future<bool> setReminder(
    File file, {
    required DateTime date,
    required ReminderKind kind,
    required ReminderLead lead,
  }) async {
    final day = DateTime(date.year, date.month, date.day);
    if (!day.isAfter(today())) {
      throw Exception('Choose a date in the future');
    }
    await _ready;
    final root = await StorageService.rootDir();
    final key = _relative(root, file.path);
    final existing = _reminders[key];
    final reminder = DocumentReminder(
      id: existing?.id ?? _nextId++,
      date: day,
      kind: kind,
      lead: lead,
    );
    _reminders[key] = reminder;
    await _saved();
    return _requestPermission();
  }

  static Future<void> removeReminder(File file) async {
    await _ready;
    final root = await StorageService.rootDir();
    if (_reminders.remove(_relative(root, file.path)) == null) return;
    await _saved();
  }

  /// Called by [StorageService] after a rename or move so reminders follow
  /// the document (or every document inside a renamed folder).
  static Future<void> recordMove(String fromPath, String toPath) async {
    await _ready;
    final root = await StorageService.rootDir();
    final from = _relative(root, fromPath);
    final to = _relative(root, toPath);
    var changed = false;
    for (final key in _reminders.keys.toList()) {
      if (key == from || p.posix.isWithin(from, key)) {
        _reminders[to + key.substring(from.length)] = _reminders.remove(key)!;
        changed = true;
      }
    }
    // Rescheduled too, since the notification text names the document.
    if (changed) await _saved();
  }

  /// Called by [StorageService] after a document or folder is deleted.
  static Future<void> recordDelete(String path) async {
    await _ready;
    final root = await StorageService.rootDir();
    final gone = _relative(root, path);
    var changed = false;
    for (final key in _reminders.keys.toList()) {
      if (key == gone || p.posix.isWithin(gone, key)) {
        _reminders.remove(key);
        changed = true;
      }
    }
    if (changed) await _saved();
  }

  // --- Notifications ---------------------------------------------------------

  static Future<bool> _requestPermission() async {
    try {
      if (Platform.isAndroid) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission() ??
            true;
      }
      if (Platform.isIOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, sound: true) ??
            false;
      }
    } catch (_) {
      // Treated as allowed: scheduling still works if the user enables
      // notifications later in system settings.
    }
    return true;
  }

  // Each reminder owns two notification ids: the advance one and the
  // on-the-day one.
  static int _advanceId(DocumentReminder r) => r.id * 2;
  static int _onDayId(DocumentReminder r) => r.id * 2 + 1;

  static Future<void> _schedule(String key, DocumentReminder r) async {
    final name = p.basenameWithoutExtension(key);
    final dateText = formatDate(r.date);
    if (r.lead != ReminderLead.onTheDay) {
      await _scheduleAt(
        id: _advanceId(r),
        at: notifyTime(r.date, r.lead),
        title: '$name ${r.kind.verb} ${r.lead.relative}',
        body: '${r.kind.label} on $dateText. Tap to open the document.',
        payload: key,
      );
    }
    await _scheduleAt(
      id: _onDayId(r),
      at: notifyTime(r.date, ReminderLead.onTheDay),
      title: '$name ${r.kind.verb} today',
      body: '${r.kind.label} on $dateText. Tap to open the document.',
      payload: key,
    );
  }

  static Future<void> _scheduleAt({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required String payload,
  }) async {
    if (!at.isAfter(DateTime.now())) return;
    try {
      await _plugin.zonedSchedule(
        id: id,
        scheduledDate: tz.TZDateTime(
          tz.local,
          at.year,
          at.month,
          at.day,
          at.hour,
        ),
        notificationDetails: _details,
        // Inexact is fine for a morning reminder and avoids the special
        // exact-alarm permission on Android 14+.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
        payload: payload,
      );
    } catch (e) {
      debugPrint('Could not schedule reminder: $e');
    }
  }

  /// Rebuilds every pending notification from the saved reminders, so they
  /// always match what's saved and follow time zone changes.
  static Future<void> _rescheduleAll() async {
    try {
      await _plugin.cancelAllPendingNotifications();
    } catch (e) {
      debugPrint('Could not clear reminders: $e');
    }
    final upcoming = _reminders.entries.where((e) => !e.value.isPast).toList()
      ..sort((a, b) => a.value.date.compareTo(b.value.date));
    for (final e in upcoming.take(_maxScheduled)) {
      await _schedule(e.key, e.value);
    }
  }

  /// Persists a change, refreshes listeners and the scheduled notifications.
  static Future<void> _saved() async {
    await _save();
    revision.value++;
    await _rescheduleAll();
  }

  /// Drops reminders whose document was removed outside the app's own
  /// delete actions.
  static Future<void> _pruneMissing() async {
    final root = await StorageService.rootDir();
    final before = _reminders.length;
    _reminders.removeWhere(
      (key, _) => !File(_absolute(root, key)).existsSync(),
    );
    if (_reminders.length == before) return;
    await _save();
    revision.value++;
  }

  // --- Storage ---------------------------------------------------------------

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'reminders.json'));
  }

  static Future<void> _save() async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'next': _nextId,
        'items': _reminders.map((k, v) => MapEntry(k, v.toJson())),
      }),
    );
  }

  static String _relative(Directory root, String path) =>
      p.posix.joinAll(p.split(p.relative(path, from: root.path)));

  static String _absolute(Directory root, String key) =>
      p.joinAll([root.path, ...p.posix.split(key)]);
}
