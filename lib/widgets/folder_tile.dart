import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../utils/format_date.dart';
import 'item_row.dart';

/// Row used for both top-level folders (in [HomeScreen]) and subfolders
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

  static const _folderColor = Color(0xFFDDA75F);

  @override
  Widget build(BuildContext context) {
    final count = folder.listSync().length;
    return ItemRow(
      leading: const Icon(
        FluentIcons.folder_24_filled,
        color: _folderColor,
        size: kItemRowLeadingWidth,
      ),
      title: p.basename(folder.path),
      subtitle: '$count item${count == 1 ? '' : 's'}',
      date: formatDate(folder.statSync().modified),
      onTap: onTap,
      onLongPress: onMore,
      trailing: IconButton(
        onPressed: onMore,
        icon: const Icon(FluentIcons.more_vertical_24_regular, size: 18),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
    );
  }
}
