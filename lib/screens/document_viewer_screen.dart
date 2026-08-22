import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_dialogs.dart';

class DocumentViewerScreen extends StatelessWidget {
  const DocumentViewerScreen({super.key, required this.file});

  final File file;

  Future<void> _delete(BuildContext context) async {
    final confirmed = await AppDialogs.confirmDelete(
      context,
      title: 'Delete document?',
      message: '"${p.basename(file.path)}" will be permanently deleted.',
    );
    if (confirmed == true) {
      await StorageService.deleteDocument(file);
      if (context.mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isImage = StorageService.isImage(file);
    return Scaffold(
      backgroundColor: isImage ? AppColors.neutral1300 : null,
      appBar: AppBar(
        backgroundColor: isImage ? AppColors.neutral1300 : null,
        foregroundColor: isImage ? AppColors.neutral0 : null,
        iconTheme: isImage
            ? const IconThemeData(color: AppColors.neutral0)
            : null,
        titleTextStyle: isImage
            ? const TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.neutral0,
              )
            : null,
        title: Text(p.basename(file.path), overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(FluentIcons.delete_24_regular),
            onPressed: () => _delete(context),
          ),
          const SizedBox(width: AppSpacing.s2),
        ],
      ),
      body: isImage
          ? Center(child: InteractiveViewer(child: Image.file(file)))
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s7),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: const BoxDecoration(
                        color: AppColors.primary25,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        FluentIcons.document_24_filled,
                        size: 44,
                        color: AppColors.primary700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s6),
                    Text(
                      p.basename(file.path),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.s7),
                    FilledButton.icon(
                      icon: const Icon(FluentIcons.open_24_regular, size: 18),
                      label: const Text('Open with...'),
                      onPressed: () => OpenFilex.open(file.path),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
