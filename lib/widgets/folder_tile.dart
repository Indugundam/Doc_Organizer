import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Card used for both top-level folders (in [HomeScreen]) and subfolders
/// (in [FolderScreen]) so the two look and behave identically.
class FolderTile extends StatelessWidget {
  const FolderTile({
    super.key,
    required this.folder,
    required this.onTap,
    required this.onMore,
  });

  final Directory folder;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final count = folder.listSync().length;
    return Card(
      child: InkWell(
        onTap: onTap,
        onLongPress: onMore,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary25,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      FluentIcons.folder_24_filled,
                      color: AppColors.primary700,
                      size: 22,
                    ),
                  ),
                  IconButton(
                    onPressed: onMore,
                    icon: const Icon(
                      FluentIcons.more_vertical_24_regular,
                      size: 18,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                p.basename(folder.path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: AppSpacing.s1),
              Text(
                '$count item${count == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
