import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'google_config.dart';
import 'storage_service.dart';

enum SyncPhase { notConfigured, signedOut, idle, syncing, error }

@immutable
class SyncStatus {
  const SyncStatus(this.phase, {this.email, this.lastSynced, this.message});

  final SyncPhase phase;
  final String? email;
  final DateTime? lastSynced;
  final String? message;
}

/// One-way backup of the local `DocManager` directory to a `DocManager`
/// folder in the user's Google Drive. The device is the source of truth:
/// nothing is ever downloaded or changed on the device.
///
/// Uses the `drive.file` scope, so the app only ever sees files it created
/// itself, never the rest of the user's Drive.
///
/// A small state file maps every local relative path to the Drive file ID it
/// was uploaded as, plus the local/remote modified times at that upload.
/// Each sync makes Drive match the device:
/// - new on the device -> uploaded.
/// - changed on the device, or edited in Drive -> device copy re-uploaded.
/// - renamed/moved on the device ([recordLocalMove] re-keys the state), or
///   renamed/moved in Drive -> the Drive copy is renamed/moved back to match.
/// - deleted on the device -> moved to Drive's trash.
/// - deleted from Drive -> uploaded again.
///
/// Files in Drive the state doesn't know about (from another device, an
/// earlier install or another sign-in) are linked when they sit at the same
/// path, and otherwise left alone - never deleted.
class SyncService {
  static const _scopes = [drive.DriveApi.driveFileScope];
  static const _folderMime = 'application/vnd.google-apps.folder';
  static const _remoteRootName = 'DocManager';
  static const _debounce = Duration(seconds: 2);

  static final status = ValueNotifier<SyncStatus>(
    const SyncStatus(SyncPhase.notConfigured),
  );

  static GoogleSignInAccount? _account;
  static _SyncState _state = _SyncState();
  static Future<void>? _initFuture;
  static Timer? _timer;
  static bool _running = false;
  static bool _again = false;

  static Future<void> init() => _initFuture ??= _init();

  static Future<void> _init() async {
    if (!GoogleConfig.isConfigured) return;
    try {
      _state = await _SyncState.load();
      await GoogleSignIn.instance.initialize(
        clientId: Platform.isIOS ? GoogleConfig.iosClientId : null,
        serverClientId: Platform.isAndroid ? GoogleConfig.webClientId : null,
      );
      AppLifecycleListener(onResume: requestSync);
      final account = await GoogleSignIn.instance
          .attemptLightweightAuthentication();
      if (account == null) {
        _setStatus(SyncPhase.signedOut);
        return;
      }
      _account = account;
      _setStatus(SyncPhase.idle);
      requestSync();
    } catch (e) {
      _setStatus(SyncPhase.signedOut, message: _describe(e));
    }
  }

  // --- Account ---------------------------------------------------------------

  /// Interactive sign-in. Must be triggered from a user action (button tap).
  static Future<void> signIn() async {
    await init();
    final account = await GoogleSignIn.instance.authenticate(
      scopeHint: _scopes,
    );
    await account.authorizationClient.authorizeScopes(_scopes);
    if (_state.account != account.email) {
      // A different account has a different Drive; file IDs from the old
      // one mean nothing there.
      _state = _SyncState()..account = account.email;
      await _state.save();
    }
    _account = account;
    _setStatus(SyncPhase.idle);
    await syncNow();
  }

  /// Stops syncing. Files stay on the device and in Drive.
  static Future<void> signOut() async {
    _timer?.cancel();
    await GoogleSignIn.instance.signOut();
    _account = null;
    _state = _SyncState();
    await _state.save();
    _setStatus(SyncPhase.signedOut);
  }

  // --- Triggers --------------------------------------------------------------

  /// Schedules a sync shortly, coalescing bursts of changes into one run.
  static void requestSync() {
    if (_account == null) return;
    _timer?.cancel();
    _timer = Timer(_debounce, _run);
  }

  static Future<void> syncNow() {
    _timer?.cancel();
    return _run();
  }

  /// Called by [StorageService] after it renames a file or folder, so the
  /// next sync renames the Drive copy instead of deleting and re-uploading.
  static Future<void> recordLocalMove(String fromPath, String toPath) async {
    final root = await StorageService.rootDir();
    _state.rekey(_relative(root, fromPath), _relative(root, toPath));
    await _state.save();
  }

  // --- Running ---------------------------------------------------------------

  static Future<void> _run() async {
    if (_account == null) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    _setStatus(SyncPhase.syncing);
    try {
      do {
        _again = false;
        await _syncOnce();
      } while (_again);
      _state.lastSynced = DateTime.now();
      _setStatus(SyncPhase.idle);
    } on _NeedsSignIn {
      _account = null;
      _setStatus(
        SyncPhase.signedOut,
        message: 'Google Drive access expired. Tap to sign in again.',
      );
    } catch (e) {
      _setStatus(SyncPhase.error, message: _describe(e));
    } finally {
      _running = false;
      await _state.save();
    }
  }

  static Future<void> _syncOnce() async {
    final authorization = await _account!.authorizationClient
        .authorizationForScopes(_scopes);
    if (authorization == null) throw _NeedsSignIn();
    final client = authorization.authClient(scopes: _scopes);
    try {
      final api = drive.DriveApi(client);
      final root = await StorageService.rootDir();
      final rootId = await _ensureRemoteRoot(api);
      final local = await _scanLocal(root);
      final remote = await _scanRemote(api, rootId);
      await _mirror(api, root, rootId, local, remote);
      await _trashDeleted(api, local, remote);
    } finally {
      client.close();
    }
  }

  /// Finds (or creates) the app's root folder in Drive. If it changed since
  /// the last sync - e.g. the user deleted it in Drive - the old file IDs
  /// are dropped and everything is uploaded again.
  static Future<String> _ensureRemoteRoot(drive.DriveApi api) async {
    final known = _state.rootId;
    if (known != null) {
      try {
        final file =
            await api.files.get(known, $fields: 'id, trashed') as drive.File;
        if (file.trashed != true) return known;
      } on drive.DetailedApiRequestError catch (e) {
        if (e.status != 404) rethrow;
      }
    }

    final existing = await api.files.list(
      q:
          "name = '$_remoteRootName' and mimeType = '$_folderMime' "
          "and 'root' in parents and trashed = false",
      $fields: 'files(id)',
      spaces: 'drive',
    );
    final id =
        existing.files?.firstOrNull?.id ??
        (await api.files.create(
          drive.File()
            ..name = _remoteRootName
            ..mimeType = _folderMime,
          $fields: 'id',
        )).id!;

    if (id != known) {
      _state.entries.clear();
      _state.rootId = id;
    }
    return id;
  }

  /// Makes every local folder and file exist in Drive, in the right place,
  /// with the current content.
  static Future<void> _mirror(
    drive.DriveApi api,
    Directory root,
    String rootId,
    Map<String, _LocalItem> local,
    _RemoteTree remote,
  ) async {
    // Parents sort before children, so a folder always exists in Drive (and
    // its ID is known) before anything inside it is handled.
    final folderIds = <String, String>{'.': rootId};
    final claimed = {for (final e in _state.entries.values) e.id};

    for (final path in _sortedByDepth(local.keys)) {
      final l = local[path]!;
      final parentId = folderIds[p.posix.dirname(path)];
      if (parentId == null) continue; // Parent failed; retry next sync.
      final name = p.posix.basename(path);

      var s = _state.entries[path];
      if (s != null && s.isDir != l.isDir) {
        _state.entries.remove(path); // Replaced by a file/folder of the
        s = null; //                   other kind; treat as new.
      }
      var r = s == null ? null : remote.byId[s.id];

      // Not tracked (first sync, new sign-in, reinstall, or deleted from
      // Drive): reuse an untracked Drive item at the same path, if any.
      if (r == null) {
        final candidate = remote.byPath[path];
        if (candidate != null &&
            candidate.isDir == l.isDir &&
            !claimed.contains(candidate.id)) {
          r = candidate;
          claimed.add(r.id);
          if (!l.isDir && l.size == r.size) {
            // Same file already backed up; just start tracking it.
            s = _SyncEntry(r.id, localMs: l.modifiedMs, remoteMs: r.modifiedMs);
            _state.entries[path] = s;
          } else {
            s = null;
          }
        }
      }

      if (r == null) {
        final id = await _create(api, root, path, l, parentId);
        if (l.isDir) folderIds[path] = id;
        claimed.add(id);
        continue;
      }

      // Renamed or moved (here, or by someone in Drive): put it back where
      // the device has it.
      if (r.parentId != parentId || r.name != name) {
        final sameParent = r.parentId == parentId;
        final metadata = drive.File()..name = name;
        // Pin the modified time so a rename alone doesn't look like a
        // content edit and trigger a re-upload next time.
        if (!l.isDir) {
          metadata.modifiedTime = DateTime.fromMillisecondsSinceEpoch(
            r.modifiedMs,
          ).toUtc();
        }
        await api.files.update(
          metadata,
          r.id,
          addParents: sameParent ? null : parentId,
          removeParents: sameParent ? null : r.parentId,
          $fields: 'id',
        );
      }

      if (l.isDir) {
        folderIds[path] = r.id;
        _state.entries[path] = _SyncEntry(r.id, isDir: true);
      } else if (s == null ||
          s.localMs != l.modifiedMs ||
          s.remoteMs != r.modifiedMs) {
        await _uploadContent(api, root, path, l, existingId: r.id);
      }
    }
  }

  /// Moves Drive copies of anything deleted on the device to Drive's trash,
  /// where they stay recoverable for 30 days.
  static Future<void> _trashDeleted(
    drive.DriveApi api,
    Map<String, _LocalItem> local,
    _RemoteTree remote,
  ) async {
    final trashed = <String>[];
    for (final path in _sortedByDepth(_state.entries.keys)) {
      if (local.containsKey(path)) continue;
      final id = _state.entries.remove(path)!.id;
      // Trashing a folder trashes everything inside it.
      if (trashed.any((t) => p.posix.isWithin(t, path))) continue;
      if (remote.byId.containsKey(id)) {
        await api.files.update(drive.File()..trashed = true, id);
      }
      trashed.add(path);
    }
  }

  // --- Uploads ---------------------------------------------------------------

  static Future<String> _create(
    drive.DriveApi api,
    Directory root,
    String path,
    _LocalItem l,
    String parentId,
  ) async {
    if (l.isDir) {
      final created = await api.files.create(
        drive.File()
          ..name = p.posix.basename(path)
          ..mimeType = _folderMime
          ..parents = [parentId],
        $fields: 'id',
      );
      _state.entries[path] = _SyncEntry(created.id!, isDir: true);
      return created.id!;
    }
    return _uploadContent(api, root, path, l, parentId: parentId);
  }

  /// Uploads the file's content, either as a new Drive file in [parentId] or
  /// over the existing one at [existingId].
  static Future<String> _uploadContent(
    drive.DriveApi api,
    Directory root,
    String path,
    _LocalItem l, {
    String? parentId,
    String? existingId,
  }) async {
    final file = File(_absolute(root, path));
    final media = drive.Media(file.openRead(), l.size);
    final options = l.size > 5 * 1024 * 1024
        ? drive.UploadOptions.resumable
        : drive.UploadOptions.defaultOptions;
    // Keep the device's modified date so Drive shows when the document was
    // actually added, not when it was backed up.
    final metadata = drive.File()
      ..modifiedTime = DateTime.fromMillisecondsSinceEpoch(
        l.modifiedMs,
      ).toUtc();
    final drive.File result;
    if (existingId != null) {
      result = await api.files.update(
        metadata,
        existingId,
        uploadMedia: media,
        uploadOptions: options,
        $fields: 'id, modifiedTime',
      );
    } else {
      result = await api.files.create(
        metadata
          ..name = p.posix.basename(path)
          ..parents = [parentId!],
        uploadMedia: media,
        uploadOptions: options,
        $fields: 'id, modifiedTime',
      );
    }
    _state.entries[path] = _SyncEntry(
      result.id!,
      localMs: l.modifiedMs,
      remoteMs: result.modifiedTime?.millisecondsSinceEpoch,
    );
    return result.id!;
  }

  // --- Scanning --------------------------------------------------------------

  static Future<Map<String, _LocalItem>> _scanLocal(Directory root) async {
    final items = <String, _LocalItem>{};
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      final key = _relative(root, entity.path);
      if (_isHidden(key)) continue;
      final stat = await entity.stat();
      if (stat.type == FileSystemEntityType.link) continue;
      items[key] = _LocalItem(
        isDir: stat.type == FileSystemEntityType.directory,
        modifiedMs: stat.modified.millisecondsSinceEpoch,
        size: stat.size,
      );
    }
    return items;
  }

  static Future<_RemoteTree> _scanRemote(
    drive.DriveApi api,
    String rootId,
  ) async {
    final tree = _RemoteTree();
    final pending = <(String, String)>[(rootId, '.')];
    while (pending.isNotEmpty) {
      final (folderId, folderPath) = pending.removeLast();
      String? pageToken;
      do {
        final page = await api.files.list(
          q: "'$folderId' in parents and trashed = false",
          $fields:
              'nextPageToken, files(id, name, mimeType, modifiedTime, size)',
          pageSize: 1000,
          pageToken: pageToken,
          spaces: 'drive',
        );
        for (final f in page.files ?? const <drive.File>[]) {
          final name = f.name ?? '';
          if (name.isEmpty) continue;
          final path = folderPath == '.'
              ? name
              : p.posix.join(folderPath, name);
          final isDir = f.mimeType == _folderMime;
          final item = _RemoteItem(
            id: f.id!,
            name: name,
            parentId: folderId,
            isDir: isDir,
            modifiedMs: f.modifiedTime?.millisecondsSinceEpoch ?? 0,
            size: int.tryParse(f.size ?? '') ?? 0,
          );
          tree.byId[item.id] = item;
          tree.byPath.putIfAbsent(path, () => item);
          if (isDir) pending.add((item.id, path));
        }
        pageToken = page.nextPageToken;
      } while (pageToken != null);
    }
    return tree;
  }

  // --- Helpers ---------------------------------------------------------------

  static List<String> _sortedByDepth(Iterable<String> paths) {
    int depth(String s) => '/'.allMatches(s).length;
    return paths.toList()..sort((a, b) {
      final byDepth = depth(a).compareTo(depth(b));
      return byDepth != 0 ? byDepth : a.compareTo(b);
    });
  }

  /// Local paths are stored relative to the DocManager root, always with
  /// forward slashes.
  static String _relative(Directory root, String path) =>
      p.posix.joinAll(p.split(p.relative(path, from: root.path)));

  static String _absolute(Directory root, String key) =>
      p.joinAll([root.path, ...p.posix.split(key)]);

  static bool _isHidden(String key) =>
      p.posix.split(key).any((segment) => segment.startsWith('.'));

  static String _describe(Object e) {
    if (e is SocketException) return 'No internet connection';
    if (e is GoogleSignInException) return e.description ?? e.code.name;
    return e.toString().replaceFirst('Exception: ', '');
  }

  static void _setStatus(SyncPhase phase, {String? message}) {
    status.value = SyncStatus(
      phase,
      email: _account?.email,
      lastSynced: _state.lastSynced,
      message: message,
    );
  }
}

class _NeedsSignIn implements Exception {}

class _LocalItem {
  const _LocalItem({
    required this.isDir,
    required this.modifiedMs,
    required this.size,
  });

  final bool isDir;
  final int modifiedMs;
  final int size;
}

class _RemoteItem {
  const _RemoteItem({
    required this.id,
    required this.name,
    required this.parentId,
    required this.isDir,
    required this.modifiedMs,
    required this.size,
  });

  final String id;
  final String name;
  final String parentId;
  final bool isDir;
  final int modifiedMs;
  final int size;
}

class _RemoteTree {
  final byId = <String, _RemoteItem>{};

  /// First item found at each path; used only to adopt untracked items.
  final byPath = <String, _RemoteItem>{};
}

class _SyncEntry {
  _SyncEntry(this.id, {this.isDir = false, this.localMs, this.remoteMs});

  final String id;
  final bool isDir;
  final int? localMs;
  final int? remoteMs;

  Map<String, dynamic> toJson() => {
    'id': id,
    if (isDir) 'dir': true,
    'l': ?localMs,
    'r': ?remoteMs,
  };

  factory _SyncEntry.fromJson(Map<String, dynamic> json) => _SyncEntry(
    json['id'] as String,
    isDir: json['dir'] == true,
    localMs: json['l'] as int?,
    remoteMs: json['r'] as int?,
  );
}

/// What the last sync uploaded, persisted outside the DocManager directory
/// so it is never synced itself.
class _SyncState {
  String? account;
  String? rootId;
  DateTime? lastSynced;
  final entries = <String, _SyncEntry>{};

  /// Moves [from] and everything under it to [to].
  void rekey(String from, String to) {
    for (final key in entries.keys.toList()) {
      if (key == from || p.posix.isWithin(from, key)) {
        final newKey = to + key.substring(from.length);
        entries[newKey] = entries.remove(key)!;
      }
    }
  }

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'drive_sync_state.json'));
  }

  static Future<_SyncState> load() async {
    final state = _SyncState();
    try {
      final file = await _file();
      if (!await file.exists()) return state;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      state
        ..account = json['account'] as String?
        ..rootId = json['rootId'] as String?
        ..lastSynced = DateTime.tryParse(json['lastSynced'] as String? ?? '');
      final entries = json['entries'] as Map<String, dynamic>? ?? {};
      for (final e in entries.entries) {
        state.entries[e.key] = _SyncEntry.fromJson(
          e.value as Map<String, dynamic>,
        );
      }
    } catch (_) {
      // A corrupt state file just means the next sync re-links by path.
    }
    return state;
  }

  Future<void> save() async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'account': account,
        'rootId': rootId,
        'lastSynced': lastSynced?.toIso8601String(),
        'entries': entries.map((k, v) => MapEntry(k, v.toJson())),
      }),
    );
  }
}
