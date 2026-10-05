import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'storage_service.dart';

/// Text read from every document, so search can match what's written inside
/// a document and not just its file name.
///
/// - Photos and scanned PDF pages are read with on-device OCR (ML Kit).
/// - Digital PDFs use their embedded text; OCR is only the fallback for pages
///   without any.
/// - Plain-text files are read directly.
///
/// Everything happens on the device. The index is a JSON file in app
/// support storage, keyed by path relative to the DocManager root and
/// invalidated by modified time + size, so only new or changed files are
/// read again.
class SearchIndex {
  SearchIndex._();

  static const _maxPdfPages = 20;
  static const _maxOcrPagesPerPdf = 10;
  static const _maxTextFileBytes = 200 * 1024;
  static const _ocrImageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.heic',
    '.webp',
    '.bmp',
  };
  static const _plainTextExtensions = {'.txt', '.md', '.csv'};

  /// Bumped whenever more text becomes searchable, so open search results
  /// can refresh.
  static final revision = ValueNotifier<int>(0);

  /// Documents still waiting to be read in the current pass.
  static final pending = ValueNotifier<int>(0);

  static final _entries = <String, _IndexEntry>{};
  static Timer? _timer;
  static bool _running = false;
  static bool _again = false;
  static TextRecognizer? _recognizer;

  static Future<void> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        for (final e in json.entries) {
          _entries[e.key] = _IndexEntry.fromJson(
            e.value as Map<String, dynamic>,
          );
        }
      }
    } catch (_) {
      // A corrupt index is simply rebuilt.
    }
    scheduleUpdate();
  }

  /// Reads any new or changed documents shortly, coalescing bursts of
  /// changes (e.g. a multi-photo import) into one pass.
  static void scheduleUpdate() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 1), _run);
  }

  /// Called by [StorageService] after a rename so the text moves with the
  /// file instead of being read again.
  static Future<void> recordMove(String fromPath, String toPath) async {
    final root = await StorageService.rootDir();
    final from = _relative(root, fromPath);
    final to = _relative(root, toPath);
    for (final key in _entries.keys.toList()) {
      if (key == from || p.posix.isWithin(from, key)) {
        _entries[to + key.substring(from.length)] = _entries.remove(key)!;
      }
    }
    await _save();
  }

  /// Whether [file]'s name or contents contain [query] (case-insensitive).
  static bool matches(File file, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (p.basename(file.path).toLowerCase().contains(q)) return true;
    return _entryFor(file)?.lower.contains(q) ?? false;
  }

  /// A one-line excerpt of [file]'s text around the first match of [query],
  /// or null if the match isn't in the text.
  static String? snippet(File file, String query, {int radius = 40}) {
    final q = query.trim().toLowerCase();
    final entry = _entryFor(file);
    if (q.isEmpty || entry == null) return null;
    final at = entry.lower.indexOf(q);
    if (at < 0) return null;
    final start = math.max(0, at - radius);
    final end = math.min(entry.text.length, at + q.length + radius);
    final excerpt = entry.text
        .substring(start, end)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return '${start > 0 ? '…' : ''}$excerpt${end < entry.text.length ? '…' : ''}';
  }

  static _IndexEntry? _entryFor(File file) {
    final root = StorageService.cachedRootDir;
    if (root == null) return null;
    return _entries[_relative(root, file.path)];
  }

  // --- Indexing --------------------------------------------------------------

  static Future<void> _run() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _indexAll();
      } while (_again);
    } finally {
      _running = false;
      pending.value = 0;
      await _recognizer?.close();
      _recognizer = null;
    }
  }

  static Future<void> _indexAll() async {
    final root = await StorageService.rootDir();
    final stats = <String, FileStat>{};
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final key = _relative(root, entity.path);
      if (p.posix.split(key).any((s) => s.startsWith('.'))) continue;
      stats[key] = await entity.stat();
    }

    final before = _entries.length;
    _entries.removeWhere((key, _) => !stats.containsKey(key));
    var dirty = _entries.length != before;

    final todo =
        stats.entries.where((e) {
          final entry = _entries[e.key];
          return entry == null ||
              entry.modifiedMs != e.value.modified.millisecondsSinceEpoch ||
              entry.size != e.value.size;
        }).toList()
          // Newest first, so a document just added is searchable soonest.
          ..sort((a, b) => b.value.modified.compareTo(a.value.modified));

    pending.value = todo.length;
    for (final (i, e) in todo.indexed) {
      String text;
      try {
        text = await _extract(File(_absolute(root, e.key)));
      } catch (_) {
        // Unreadable (corrupt, password-protected, unsupported). Record it
        // as empty so it isn't retried until the file changes.
        text = '';
      }
      _entries[e.key] = _IndexEntry(
        modifiedMs: e.value.modified.millisecondsSinceEpoch,
        size: e.value.size,
        text: text,
      );
      dirty = true;
      pending.value = todo.length - i - 1;
      if (text.isNotEmpty) revision.value++;
      if (i % 5 == 4) await _save();
    }
    if (dirty) await _save();
  }

  static Future<String> _extract(File file) async {
    final ext = p.extension(file.path).toLowerCase();
    if (_ocrImageExtensions.contains(ext)) return _ocr(file.path);
    if (ext == '.pdf') return _pdfText(file);
    if (_plainTextExtensions.contains(ext)) {
      final bytes = await file.openRead(0, _maxTextFileBytes).fold<List<int>>(
        [],
        (all, chunk) => all..addAll(chunk),
      );
      return utf8.decode(bytes, allowMalformed: true);
    }
    return '';
  }

  static Future<String> _ocr(String imagePath) async {
    _recognizer ??= TextRecognizer();
    final result = await _recognizer!.processImage(
      InputImage.fromFilePath(imagePath),
    );
    return result.text;
  }

  static Future<String> _pdfText(File file) async {
    final doc = await PdfDocument.openFile(file.path);
    try {
      final buffer = StringBuffer();
      var ocrPages = 0;
      for (final page in doc.pages.take(_maxPdfPages)) {
        final embedded = (await page.loadText())?.fullText.trim() ?? '';
        if (embedded.length >= 20) {
          buffer.writeln(embedded);
        } else if (ocrPages < _maxOcrPagesPerPdf) {
          // No real text layer - a scan. Render the page and OCR it.
          ocrPages++;
          buffer.writeln(await _ocrPdfPage(page));
        }
      }
      return buffer.toString();
    } finally {
      await doc.dispose();
    }
  }

  static Future<String> _ocrPdfPage(PdfPage page) async {
    // ~2000px on the long side is plenty for OCR without huge memory use.
    final scale = 2000 / math.max(page.width, page.height);
    final width = (page.width * scale).round();
    final height = (page.height * scale).round();
    final rendered = await page.render(
      width: width,
      height: height,
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
      backgroundColor: 0xFFFFFFFF,
    );
    if (rendered == null) return '';
    final temp = File(
      p.join(
        (await getTemporaryDirectory()).path,
        'ocr_page_${DateTime.now().microsecondsSinceEpoch}.png',
      ),
    );
    try {
      final image = await rendered.createImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png == null) return '';
      await temp.writeAsBytes(png.buffer.asUint8List());
      return await _ocr(temp.path);
    } finally {
      rendered.dispose();
      if (await temp.exists()) await temp.delete();
    }
  }

  // --- Storage ---------------------------------------------------------------

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'search_index.json'));
  }

  static Future<void> _save() async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(_entries.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  static String _relative(Directory root, String path) =>
      p.posix.joinAll(p.split(p.relative(path, from: root.path)));

  static String _absolute(Directory root, String key) =>
      p.joinAll([root.path, ...p.posix.split(key)]);
}

class _IndexEntry {
  _IndexEntry({
    required this.modifiedMs,
    required this.size,
    required this.text,
  }) : lower = text.toLowerCase();

  final int modifiedMs;
  final int size;
  final String text;

  /// Lower-cased copy for case-insensitive matching.
  final String lower;

  Map<String, dynamic> toJson() => {'m': modifiedMs, 's': size, 't': text};

  factory _IndexEntry.fromJson(Map<String, dynamic> json) => _IndexEntry(
    modifiedMs: json['m'] as int,
    size: json['s'] as int,
    text: json['t'] as String,
  );
}
