import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/storage_service.dart';
import '../theme/app_spacing.dart';

/// Path from Home to [folder], e.g. Home > Bills > 2024. Tapping a crumb
/// calls [onNavigate] with how many levels up that crumb is (1 = parent).
class Breadcrumbs extends StatelessWidget {
  const Breadcrumbs({
    super.key,
    required this.folder,
    required this.onNavigate,
  });

  final Directory folder;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final root = StorageService.cachedRootDir;
    final parts = root == null
        ? [p.basename(folder.path)]
        : p.split(p.relative(folder.path, from: root.path));
    final muted = theme.colorScheme.onSurfaceVariant;

    final crumbs = <Widget>[
      _Crumb(
        onTap: () => onNavigate(parts.length),
        child: Icon(FluentIcons.home_24_regular, size: 18, color: muted),
      ),
    ];
    for (var i = 0; i < parts.length; i++) {
      final isCurrent = i == parts.length - 1;
      crumbs
        ..add(
          Icon(FluentIcons.chevron_right_24_regular, size: 14, color: muted),
        )
        ..add(
          _Crumb(
            onTap: isCurrent ? null : () => onNavigate(parts.length - 1 - i),
            child: Text(
              parts[i],
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isCurrent ? theme.colorScheme.onSurface : muted,
                fontWeight: isCurrent ? FontWeight.w600 : null,
              ),
            ),
          ),
        );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerTheme.color!)),
      ),
      child: SizedBox(
        height: 40,
        // Reversed so a deep path stays scrolled to the current folder.
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
          child: Row(children: crumbs),
        ),
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s3,
        ),
        child: child,
      ),
    );
  }
}
