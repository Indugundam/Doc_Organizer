import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../utils/format_date.dart';
import 'item_views.dart';

/// Row or grid card used for both top-level folders (in [HomeScreen]) and
/// subfolders (in [FolderScreen]) so the two look and behave identically.
class FolderTile extends StatelessWidget {
  const FolderTile({
    super.key,
    required this.folder,
    required this.onTap,
    required this.onMore,
    this.grid = false,
  });

  final Directory folder;
  final VoidCallback onTap;
  final VoidCallback onMore;

  /// Show as an [ItemCard] instead of an [ItemRow].
  final bool grid;

  static const _folderColor = Color.fromARGB(255, 221, 172, 108);

  @override
  Widget build(BuildContext context) {
    final count = folder.listSync().length;
    final title = p.basename(folder.path);
    final subtitle = '$count item${count == 1 ? '' : 's'}';
    final date = formatDate(folder.statSync().modified);
    final more = IconButton(
      onPressed: onMore,
      icon: const Icon(FluentIcons.more_vertical_24_regular, size: 18),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
    if (grid) {
      return ItemCard(
        preview: ColoredBox(
          color: _folderColor.withValues(alpha: 0.12),
          child: const Center(
            child: Icon(
              FluentIcons.folder_24_filled,
              color: _folderColor,
              size: 72,
            ),
          ),
        ),
        title: title,
        subtitle: subtitle,
        date: date,
        onTap: onTap,
        onLongPress: onMore,
        trailing: more,
      );
    }
    return ItemRow(
      leading: const Icon(
        FluentIcons.folder_24_filled,
        color: _folderColor,
        size: kItemRowLeadingWidth,
      ),
      title: title,
      subtitle: subtitle,
      date: date,
      onTap: onTap,
      onLongPress: onMore,
      trailing: more,
    );
  }
}
