import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// One action row shown in [AppDialogs.showActionSheet].
class AppSheetAction {
  const AppSheetAction({
    required this.id,
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  final String id;
  final IconData icon;
  final String label;
  final bool destructive;
}

/// Shared dialog/bottom-sheet/alert helpers so every confirmation, prompt,
/// and action menu in the app looks and behaves the same way.
class AppDialogs {
  AppDialogs._();

  static Future<String?> promptForName(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String confirmLabel,
    String initial = '',
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(
          AppSpacing.s6,
          AppSpacing.s6,
          AppSpacing.s6,
          AppSpacing.s3,
        ),
        contentPadding: const EdgeInsets.fromLTRB(
          AppSpacing.s6,
          0,
          AppSpacing.s6,
          AppSpacing.s5,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.s6,
          0,
          AppSpacing.s6,
          AppSpacing.s5,
        ),
        title: Row(
          children: [
            _DialogIcon(icon: icon),
            const SizedBox(width: AppSpacing.s4),
            Expanded(child: Text(title)),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Bills, Hospital'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  static Future<bool?> confirmDelete(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(
          AppSpacing.s6,
          AppSpacing.s6,
          AppSpacing.s6,
          AppSpacing.s3,
        ),
        contentPadding: const EdgeInsets.fromLTRB(
          AppSpacing.s6,
          0,
          AppSpacing.s6,
          AppSpacing.s5,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.s6,
          0,
          AppSpacing.s6,
          AppSpacing.s5,
        ),
        title: Row(
          children: [
            const _DialogIcon(
              icon: FluentIcons.delete_24_regular,
              background: AppColors.errorBg,
              foreground: AppColors.error500,
            ),
            const SizedBox(width: AppSpacing.s4),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error500,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  static Future<String?> showActionSheet(
    BuildContext context, {
    required List<AppSheetAction> actions,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: actions
                .map(
                  (action) => ListTile(
                    leading: Icon(
                      action.icon,
                      color: action.destructive
                          ? AppColors.error500
                          : AppColors.neutral700,
                    ),
                    title: Text(
                      action.label,
                      style: TextStyle(
                        color: action.destructive
                            ? AppColors.error500
                            : AppColors.neutral1300,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, action.id),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _DialogIcon extends StatelessWidget {
  const _DialogIcon({
    required this.icon,
    this.background = AppColors.primary25,
    this.foreground = AppColors.primary700,
  });

  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, color: foreground, size: 20),
    );
  }
}
