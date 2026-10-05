import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../services/storage_service.dart';
import '../utils/file_type_style.dart';
import 'video_thumbnail_preview.dart';

/// Preview for any document: the image itself, a video frame, the first page
/// of a PDF, or a file-type icon for everything else.
class DocumentThumbnail extends StatelessWidget {
  const DocumentThumbnail({super.key, required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    if (StorageService.isImage(file)) {
      // Decode at thumbnail size instead of full camera resolution.
      return Image.file(
        file,
        fit: BoxFit.cover,
        cacheWidth: 400,
        errorBuilder: (context, error, stack) => _FileTypeIcon(file: file),
      );
    }
    if (StorageService.isVideo(file)) return VideoThumbnailPreview(file: file);
    if (p.extension(file.path).toLowerCase() == '.pdf') {
      return _PdfThumbnail(file: file);
    }
    return _FileTypeIcon(file: file);
  }
}

class _FileTypeIcon extends StatelessWidget {
  const _FileTypeIcon({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    final style = fileTypeStyleFor(file);
    return Container(
      color: style.background,
      child: Center(child: Icon(style.icon, size: 36, color: style.color)),
    );
  }
}

class _PdfThumbnail extends StatefulWidget {
  const _PdfThumbnail({required this.file});

  final File file;

  @override
  State<_PdfThumbnail> createState() => _PdfThumbnailState();
}

class _PdfThumbnailState extends State<_PdfThumbnail> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = PdfThumbnailCache.load(widget.file);
  }

  @override
  void didUpdateWidget(_PdfThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _future = PdfThumbnailCache.load(widget.file);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return _FileTypeIcon(file: widget.file);
        return Container(
          color: Colors.white,
          alignment: Alignment.topCenter,
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: double.infinity,
            alignment: Alignment.topCenter,
            gaplessPlayback: true,
          ),
        );
      },
    );
  }
}

/// Renders the first page of a PDF once and keeps it as a small PNG in the
/// app's cache directory, so scrolling a folder doesn't re-render PDFs.
/// Cache entries are keyed by path + modified time + size, so a changed or
/// renamed file simply gets a fresh thumbnail.
class PdfThumbnailCache {
  PdfThumbnailCache._();

  static const _widthPx = 400;
  static final _inFlight = <String, Future<Uint8List?>>{};

  static Future<Uint8List?> load(File file) async {
    final FileStat stat;
    try {
      stat = await file.stat();
    } catch (_) {
      return null;
    }
    final key = _hash(
      '${file.path}|${stat.modified.millisecondsSinceEpoch}|${stat.size}',
    );
    // Many tiles can ask for the same PDF at once (e.g. on rebuild); share
    // one render.
    return _inFlight.putIfAbsent(key, () async {
      try {
        return await _loadOrRender(file, key);
      } finally {
        _inFlight.remove(key);
      }
    });
  }

  static Future<Uint8List?> _loadOrRender(File file, String key) async {
    final dir = Directory(
      p.join((await getApplicationCacheDirectory()).path, 'pdf_thumbnails'),
    );
    final cached = File(p.join(dir.path, '$key.png'));
    if (await cached.exists()) return cached.readAsBytes();

    try {
      final doc = await PdfDocument.openFile(file.path);
      try {
        if (doc.pages.isEmpty) return null;
        final page = doc.pages.first;
        final height = (_widthPx * page.height / page.width).round();
        final rendered = await page.render(
          width: _widthPx,
          height: height,
          fullWidth: _widthPx.toDouble(),
          fullHeight: height.toDouble(),
          backgroundColor: 0xFFFFFFFF,
        );
        if (rendered == null) return null;
        try {
          final image = await rendered.createImage();
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          if (png == null) return null;
          final bytes = png.buffer.asUint8List();
          await dir.create(recursive: true);
          await cached.writeAsBytes(bytes);
          return bytes;
        } finally {
          rendered.dispose();
        }
      } finally {
        await doc.dispose();
      }
    } catch (_) {
      return null; // Corrupt or password-protected; show the PDF icon.
    }
  }

  /// FNV-1a; stable across runs, unlike String.hashCode.
  static String _hash(String input) {
    var hash = 0xcbf29ce484222325;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16);
  }
}
