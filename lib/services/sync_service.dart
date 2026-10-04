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

/// Two-way sync between the local `DocManager` directory and a `DocManager`
/// folder in the user's Google Drive.
///
/// Uses the `drive.file` scope, so the app only ever sees files it created
/// itself (on any device signed in to the same account), never the rest of
/// the user's Drive.
///
/// Reconciliation is driven by a small state file that remembers, for every
/// relative path, the Drive file ID and the local/remote modified times seen
/// at the last successful sync. Comparing against it tells us which side
/// changed:
/// - present on one side only, and known in state -> deleted on the other
///   side, so delete it here too (remote deletes go to Drive's trash).
/// - present on one side only, unknown -> new, so copy it across.
/// - present on both -> whichever side changed wins; if both did, newer wins.
///
/// Renames are tracked by Drive file ID so they move the file instead of
/// re-uploading it: local renames are recorded via [recordLocalMove], and
/// remote renames show up as a known ID at a new path.
class SyncService {
  static const _scopes = [drive.DriveApi.driveFileScope];
  static const _folderMime = 'application/vnd.google-apps.folder';
  static const _remoteRootName = 'DocManager';
  static const _debounce = Duration(seconds: 2);

  static final status = ValueNotifier<SyncStatus>(
    const SyncStatus(SyncPhase.notConfigured),
  );

  /// Bumped after a sync that changed local files, so screens can reload.
  static final localChanges = ValueNotifier<int>(0);

  static GoogleSignInAccount? _account;
  static _SyncState _state = _SyncState();
  static Future<void>? _initFuture;
  static Timer? _timer;
  static bool _running = false;
  static bool _again = false;
  static bool _localDirty = false;

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
      // A different account has a different Drive; never carry state over,
      // or its absence of files would look like deletions.
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
    final from = _relative(root, fromPath);
    final to = _relative(root, toPath);
    _state.rekey(from, to);
    _state.entries[to]?.moved = true;
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
      if (_localDirty) {
        _localDirty = false;
        localChanges.value++;
      }
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

      // Apply renames one at a time, rescanning after each, because moving a
      // folder changes the paths of everything inside it.
      for (var i = 0; i < 100; i++) {
        final remote = await _scanRemote(api, rootId);
        if (!await _applyOneMove(api, root, rootId, remote)) break;
      }

      await _reconcile(api, root, rootId);
    } finally {
      client.close();
    }
  }

  /// Finds (or creates) the app's root folder in Drive. If it changed since
  /// the last sync - e.g. the user deleted it in Drive - the old state is
  /// dropped so nothing is mistaken for a deletion; the next pass then just
  /// merges both sides.
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

  /// Applies the first pending rename found, in either direction. Returns
  /// false when there is nothing left to move.
  static Future<bool> _applyOneMove(
    drive.DriveApi api,
    Directory root,
    String rootId,
    _RemoteTree remote,
  ) async {
    for (final key in _sortedByDepth(_state.entries.keys)) {
      final entry = _state.entries[key]!;
      final item = remote.byId[entry.id];
      if (item == null || item.path == key) {
        entry.moved = false;
        continue;
      }

      if (entry.moved) {
        // Renamed locally: rename/move the Drive copy to match.
        final parentId = remote.folderId(p.posix.dirname(key), rootId);
        if (parentId == null) {
          // Can't place it; forget it so it re-uploads rather than being
          // treated as deleted.
          _state.entries.remove(key);
          continue;
        }
        final sameParent = parentId == item.parentId;
        await api.files.update(
          drive.File()..name = p.posix.basename(key),
          entry.id,
          addParents: sameParent ? null : parentId,
          removeParents: sameParent ? null : item.parentId,
          $fields: 'id',
        );
        entry.moved = false;
        return true;
      }

      // Renamed in Drive: rename the local copy to match.
      final from = _absolute(root, key);
      final to = _absolute(root, item.path);
      final type = FileSystemEntity.typeSync(from, followLinks: false);
      if (type == FileSystemEntityType.notFound ||
          FileSystemEntity.typeSync(to) != FileSystemEntityType.notFound) {
        continue;
      }
      await Directory(p.dirname(to)).create(recursive: true);
      if (type == FileSystemEntityType.directory) {
        await Directory(from).rename(to);
      } else {
        await File(from).rename(to);
      }
      _state.rekey(key, item.path);
      _localDirty = true;
      return true;
    }
    return false;
  }

  static Future<void> _reconcile(
    drive.DriveApi api,
    Directory root,
    String rootId,
  ) async {
    final local = await _scanLocal(root);
    final remote = await _scanRemote(api, rootId);
    final paths = _sortedByDepth({
      ...local.keys,
      ...remote.byPath.keys,
      ..._state.entries.keys,
    });
    // Parents sort before children, so a folder is always created (and its
    // ID known) before anything inside it is uploaded.
    final folderIds = <String, String>{
      '.': rootId,
      for (final item in remote.byPath.values)
        if (item.isDir) item.path: item.id,
    };
    final removed = <String>[];

    for (final path in paths) {
      if (removed.any((r) => p.posix.isWithin(r, path))) continue;
      final l = local[path];
      final r = remote.byPath[path];
      final known = _state.entries.containsKey(path);

      if (l == null && r == null) {
        _state.entries.remove(path);
      } else if (l != null && r != null) {
        if (l.isDir != r.isDir) continue; // File vs folder clash; leave it.
        if (l.isDir) {
          _state.entries[path] = _SyncEntry(r.id, isDir: true);
        } else {
          await _reconcileFile(api, root, path, l, r, folderIds);
        }
      } else if (l != null) {
        // Only on this device. If it was synced before (and nothing new was
        // added under it since), it was deleted in Drive.
        if (known && !_hasUnsyncedUnder(path, local.keys)) {
          await _deleteLocal(root, path, l);
          removed.add(path);
        } else {
          _state.removeUnder(path);
          await _upload(api, root, path, l, folderIds);
        }
      } else {
        // Only in Drive. Same idea, mirrored.
        if (known && !_hasUnsyncedUnder(path, remote.byPath.keys)) {
          await api.files.update(drive.File()..trashed = true, r!.id);
          _state.removeUnder(path);
          removed.add(path);
        } else {
          _state.removeUnder(path);
          await _download(api, root, path, r!);
        }
      }
    }
  }

  static Future<void> _reconcileFile(
    drive.DriveApi api,
    Directory root,
    String path,
    _LocalItem l,
    _RemoteItem r,
    Map<String, String> folderIds,
  ) async {
    final s = _state.entries[path];
    final bool uploadLocal;
    if (s == null) {
      // Both sides have it but we've never linked them (first sync, or a
      // lost state file). Same size means same file; otherwise newer wins.
      if (l.size == r.size) {
        _state.entries[path] = _SyncEntry(
          r.id,
          localMs: l.modifiedMs,
          remoteMs: r.modifiedMs,
        );
        return;
      }
      uploadLocal = l.modifiedMs > r.modifiedMs;
    } else {
      final localChanged = l.modifiedMs != s.localMs;
      final remoteChanged = r.modifiedMs != s.remoteMs || s.id != r.id;
      if (!localChanged && !remoteChanged) return;
      uploadLocal =
          localChanged && (!remoteChanged || l.modifiedMs >= r.modifiedMs);
    }

    if (uploadLocal) {
      await _upload(api, root, path, l, folderIds, existingId: r.id);
    } else {
      await _download(api, root, path, r);
    }
  }

  // --- Transfers -------------------------------------------------------------

  static Future<void> _upload(
    drive.DriveApi api,
    Directory root,
    String path,
    _LocalItem l,
    Map<String, String> folderIds, {
    String? existingId,
  }) async {
    final parentId = folderIds[p.posix.dirname(path)];
    if (parentId == null) return; // Parent failed to upload; retry next sync.

    if (l.isDir) {
      final created = await api.files.create(
        drive.File()
          ..name = p.posix.basename(path)
          ..mimeType = _folderMime
          ..parents = [parentId],
        $fields: 'id',
      );
      folderIds[path] = created.id!;
      _state.entries[path] = _SyncEntry(created.id!, isDir: true);
      return;
    }

    final file = File(_absolute(root, path));
    final media = drive.Media(file.openRead(), l.size);
    final options = l.size > 5 * 1024 * 1024
        ? drive.UploadOptions.resumable
        : drive.UploadOptions.defaultOptions;
    // Carry the local modified time over so "newer wins" compares like with
    // like, and date sorting matches across devices.
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
          ..parents = [parentId],
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
  }

  static Future<void> _download(
    drive.DriveApi api,
    Directory root,
    String path,
    _RemoteItem r,
  ) async {
    final target = _absolute(root, path);
    _localDirty = true;

    if (r.isDir) {
      await Directory(target).create(recursive: true);
      _state.entries[path] = _SyncEntry(r.id, isDir: true);
      return;
    }

    // Download to a temp file first so a dropped connection never leaves a
    // half-written document in the folder.
    final media =
        await api.files.get(
              r.id,
              downloadOptions: drive.DownloadOptions.fullMedia,
            )
            as drive.Media;
    final temp = File(
      p.join((await getTemporaryDirectory()).path, 'sync_${r.id}'),
    );
    final sink = temp.openWrite();
    await media.stream.pipe(sink);
    await Directory(p.dirname(target)).create(recursive: true);
    final file = await temp.copy(target);
    await temp.delete();
    await file.setLastModified(
      DateTime.fromMillisecondsSinceEpoch(r.modifiedMs),
    );
    _state.entries[path] = _SyncEntry(
      r.id,
      localMs: (await file.lastModified()).millisecondsSinceEpoch,
      remoteMs: r.modifiedMs,
    );
  }

  static Future<void> _deleteLocal(
    Directory root,
    String path,
    _LocalItem l,
  ) async {
    final target = _absolute(root, path);
    if (l.isDir) {
      await Directory(target).delete(recursive: true);
    } else {
      await File(target).delete();
    }
    _state.removeUnder(path);
    _localDirty = true;
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
          final name = _safeName(f.name ?? '');
          final isDir = f.mimeType == _folderMime;
          // Google Docs/Sheets have no file content to download; skip them.
          final isNativeDoc =
              !isDir &&
              (f.mimeType?.startsWith('application/vnd.google-apps.') ?? false);
          if (name.isEmpty || name.startsWith('.') || isNativeDoc) continue;
          final path = folderPath == '.'
              ? name
              : p.posix.join(folderPath, name);
          if (tree.byPath.containsKey(path)) continue; // Duplicate name.
          final item = _RemoteItem(
            id: f.id!,
            path: path,
            parentId: folderId,
            isDir: isDir,
            modifiedMs: f.modifiedTime?.millisecondsSinceEpoch ?? 0,
            size: int.tryParse(f.size ?? '') ?? 0,
          );
          tree.byPath[path] = item;
          tree.byId[item.id] = item;
          if (isDir) pending.add((item.id, path));
        }
        pageToken = page.nextPageToken;
      } while (pageToken != null);
    }
    return tree;
  }

  // --- Helpers ---------------------------------------------------------------

  /// Whether anything under [path] has never been synced - i.e. was added
  /// after the last sync and must not be lost with a folder delete.
  static bool _hasUnsyncedUnder(String path, Iterable<String> keys) => keys.any(
    (k) => p.posix.isWithin(path, k) && !_state.entries.containsKey(k),
  );

  static List<String> _sortedByDepth(Iterable<String> paths) {
    int depth(String s) => '/'.allMatches(s).length;
    return paths.toList()..sort((a, b) {
      final byDepth = depth(a).compareTo(depth(b));
      return byDepth != 0 ? byDepth : a.compareTo(b);
    });
  }

  /// Local paths are stored relative to the DocManager root, always with
  /// forward slashes, so they match Drive paths.
  static String _relative(Directory root, String path) =>
      p.posix.joinAll(p.split(p.relative(path, from: root.path)));

  static String _absolute(Directory root, String key) =>
      p.joinAll([root.path, ...p.posix.split(key)]);

  static bool _isHidden(String key) =>
      p.posix.split(key).any((segment) => segment.startsWith('.'));

  static String _safeName(String name) =>
      name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

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
    required this.path,
    required this.parentId,
    required this.isDir,
    required this.modifiedMs,
    required this.size,
  });

  final String id;
  final String path;
  final String parentId;
  final bool isDir;
  final int modifiedMs;
  final int size;
}

class _RemoteTree {
  final byPath = <String, _RemoteItem>{};
  final byId = <String, _RemoteItem>{};

  String? folderId(String path, String rootId) {
    if (path == '.') return rootId;
    final item = byPath[path];
    return item != null && item.isDir ? item.id : null;
  }
}

class _SyncEntry {
  _SyncEntry(this.id, {this.isDir = false, this.localMs, this.remoteMs});

  final String id;
  final bool isDir;
  final int? localMs;
  final int? remoteMs;

  /// Renamed locally; the Drive copy still needs renaming.
  bool moved = false;

  Map<String, dynamic> toJson() => {
    'id': id,
    if (isDir) 'dir': true,
    'l': ?localMs,
    'r': ?remoteMs,
    if (moved) 'moved': true,
  };

  factory _SyncEntry.fromJson(Map<String, dynamic> json) => _SyncEntry(
    json['id'] as String,
    isDir: json['dir'] == true,
    localMs: json['l'] as int?,
    remoteMs: json['r'] as int?,
  )..moved = json['moved'] == true;
}

/// What the last sync saw, persisted outside the DocManager directory so it
/// is never synced itself.
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

  void removeUnder(String path) => entries.removeWhere(
    (key, _) => key == path || p.posix.isWithin(path, key),
  );

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
