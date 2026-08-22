import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../theme/app_colors.dart';

/// Icon + color pairing used to represent a document's file type, mirroring
/// the colors commonly associated with each format (PDF red, Word blue,
/// Excel green, etc.).
class FileTypeStyle {
  const FileTypeStyle({
    required this.icon,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final Color color;
  final Color background;
}

const _pdf = FileTypeStyle(
  icon: FluentIcons.document_pdf_24_filled,
  color: Color(0xFFE5484D),
  background: Color(0xFFFDEEEE),
);
const _word = FileTypeStyle(
  icon: FluentIcons.document_text_24_filled,
  color: Color(0xFF2B67C6),
  background: Color(0xFFEAF1FC),
);
const _excel = FileTypeStyle(
  icon: FluentIcons.document_table_24_filled,
  color: Color(0xFF1E7B45),
  background: Color(0xFFE8F5EC),
);
const _slides = FileTypeStyle(
  icon: FluentIcons.slide_text_24_filled,
  color: Color(0xFFD2691E),
  background: Color(0xFFFCEEE2),
);
const _archive = FileTypeStyle(
  icon: FluentIcons.folder_zip_24_filled,
  color: Color(0xFF8A6D3B),
  background: Color(0xFFF3EEE3),
);
const _audio = FileTypeStyle(
  icon: FluentIcons.music_note_2_24_filled,
  color: Color(0xFF7C3AED),
  background: Color(0xFFF1EAFD),
);
const _text = FileTypeStyle(
  icon: FluentIcons.document_24_filled,
  color: AppColors.neutral700,
  background: AppColors.neutral50,
);
const _generic = FileTypeStyle(
  icon: FluentIcons.document_24_filled,
  color: AppColors.primary700,
  background: AppColors.primary25,
);

FileTypeStyle fileTypeStyleFor(File file) {
  switch (p.extension(file.path).toLowerCase()) {
    case '.pdf':
      return _pdf;
    case '.doc':
    case '.docx':
    case '.rtf':
      return _word;
    case '.xls':
    case '.xlsx':
    case '.csv':
      return _excel;
    case '.ppt':
    case '.pptx':
      return _slides;
    case '.zip':
    case '.rar':
    case '.7z':
    case '.tar':
    case '.gz':
      return _archive;
    case '.mp3':
    case '.wav':
    case '.m4a':
    case '.aac':
    case '.flac':
    case '.ogg':
      return _audio;
    case '.txt':
    case '.md':
      return _text;
    default:
      return _generic;
  }
}
