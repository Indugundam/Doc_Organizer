import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Width reserved for [ItemRow.leading]; also used to indent the dividers
/// between rows so they line up with the text.
const double kItemRowLeadingWidth = 52;

/// Divider placed between [ItemRow]s, indented to start under the title.
class ItemRowDivider extends StatelessWidget {
  const ItemRowDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Divider(
      indent: AppSpacing.s5 + kItemRowLeadingWidth + AppSpacing.s4,
    );
  }
}

/// List row shared by folders and documents: an icon or thumbnail, the name
/// with a detail line under it, and the date on the right.
class ItemRow extends StatelessWidget {
  const ItemRow({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.date,
    required this.trailing,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final String date;
  final Widget trailing;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Material(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s5,
            AppSpacing.s4,
            AppSpacing.s3,
            AppSpacing.s4,
          ),
          child: Row(
            children: [
              SizedBox.square(
                dimension: kItemRowLeadingWidth,
                child: Center(child: leading),
              ),
              const SizedBox(width: AppSpacing.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s2),
                        // Sits on the name's line rather than centered on
                        // the whole row.
                        SizedBox(
                          width: 32,
                          height: 24,
                          child: Center(child: trailing),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: secondary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s3),
                        Text(date, style: secondary),
                        const SizedBox(width: AppSpacing.s3),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
