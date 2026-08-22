import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// All folders and documents live as real directories/files under
/// `<app documents dir>/DocManager/<folder>/<file>`. Using the filesystem
/// directly (instead of a database) means the folder structure the user
/// sees is exactly what's on disk - nothing to migrate or corrupt.
class StorageService {
  static Directory? _root;

  static Future<Directory> _rootDir() async {
    if (_root != null) return _root!;
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'DocManager'));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    _root = root;
    return root;
  }

  static Future<List<Directory>> listFolders() async {
    final root = await _rootDir();
    final entries = await root.list().toList();
    final folders = entries.whereType<Directory>().toList();
    folders.sort(
      (a, b) => p.basename(a.path).toLowerCase().compareTo(
        p.basename(b.path).toLowerCase(),
      ),
    );
    return folders;
  }

  static Future<Directory> createFolder(String name) async {
    final root = await _rootDir();
    final dir = Directory(p.join(root.path, _sanitize(name)));
    if (await dir.exists()) {
      throw Exception('A folder named "$name" already exists');
    }
    return dir.create(recursive: true);
  }

  static Future<void> renameFolder(Directory folder, String newName) async {
    final root = await _rootDir();
    final newPath = p.join(root.path, _sanitize(newName));
    if (await Directory(newPath).exists()) {
      throw Exception('A folder named "$newName" already exists');
    }
    await folder.rename(newPath);
  }

  static Future<void> deleteFolder(Directory folder) async {
    await folder.delete(recursive: true);
  }

  static Future<List<File>> listDocuments(Directory folder) async {
    final entries = await folder.list().toList();
    final files = entries.whereType<File>().toList();
    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    return files;
  }

  /// Copies an external file (picked from camera/gallery/file picker) into
  /// [folder], giving it a collision-proof, timestamped name while keeping
  /// its original extension.
  static Future<File> importFile(Directory folder, String sourcePath) async {
    final ext = p.extension(sourcePath);
    final base = p.basenameWithoutExtension(sourcePath);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final destPath = p.join(folder.path, '${_sanitize(base)}_$stamp$ext');
    return File(sourcePath).copy(destPath);
  }

  static Future<void> deleteDocument(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  static bool isImage(File file) {
    final ext = p.extension(file.path).toLowerCase();
    return ext == '.jpg' ||
        ext == '.jpeg' ||
        ext == '.png' ||
        ext == '.heic' ||
        ext == '.webp';
  }

  static String _sanitize(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw Exception('Name cannot be empty');
    }
    return trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }
}
