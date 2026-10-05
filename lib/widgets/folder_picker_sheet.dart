import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/storage_service.dart';
import '../theme/app_spacing.dart';

/// Bottom sheet listing every folder as an indented tree. Returns the chosen
/// folder, or null if dismissed. [current] is shown but can't be picked.
Future<Directory?> showFolderPicker(
  BuildContext context, {
  required String title,
  required Directory current,
}) async {
  final root = await StorageService.rootDir();
  final folders = await StorageService.listAllFolders();
  if (!context.mounted) return null;
  return showModalBottomSheet<Directory>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (ctx, scrollController) => SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s5,
                AppSpacing.s5,
                AppSpacing.s5,
                AppSpacing.s3,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: folders.length,
                itemBuilder: (ctx, index) {
                  final folder = folders[index];
                  final depth =
                      p.split(p.relative(folder.path, from: root.path)).length -
                      1;
                  final isCurrent = p.equals(folder.path, current.path);
                  return ListTile(
                    enabled: !isCurrent,
                    contentPadding: EdgeInsets.only(
                      left: AppSpacing.s5 + depth * AppSpacing.s6,
                      right: AppSpacing.s5,
                    ),
                    leading: Icon(
                      depth == 0
                          ? FluentIcons.folder_24_regular
                          : FluentIcons.folder_arrow_right_24_regular,
                    ),
                    title: Text(
                      p.basename(folder.path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: isCurrent ? const Text('Current folder') : null,
                    onTap: () => Navigator.pop(ctx, folder),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
