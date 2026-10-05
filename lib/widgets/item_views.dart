import 'package:flutter/material.dart';

import '../services/view_mode_controller.dart';
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

/// Grid counterpart of [ItemRow]: the preview fills the top of the card and
/// the same name, menu/tick, detail line and date sit underneath.
class ItemCard extends StatelessWidget {
  const ItemCard({
    super.key,
    required this.preview,
    required this.title,
    required this.subtitle,
    required this.date,
    required this.trailing,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
  });

  final Widget preview;
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
    final primary = theme.colorScheme.primary;
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final radius = BorderRadius.circular(AppRadius.large);
    return Material(
      color: selected
          ? Color.alphaBlend(
              primary.withValues(alpha: 0.12),
              theme.colorScheme.surface,
            )
          : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: selected
            ? BorderSide(color: primary, width: 2)
            : BorderSide(color: theme.colorScheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: preview),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                AppSpacing.s3,
                AppSpacing.s2,
                AppSpacing.s4,
              ),
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
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        height: 24,
                        child: Center(child: trailing),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.s3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: secondary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s2),
                        Text(date, style: secondary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grid layout shared by every screen so all cards are the same size.
const kItemGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 220,
  crossAxisSpacing: AppSpacing.s4,
  mainAxisSpacing: AppSpacing.s4,
  childAspectRatio: 0.8,
);

/// Shows items as [ItemRow]s or [ItemCard]s depending on
/// [ViewModeController.mode], rebuilding when the user toggles the view.
/// [itemBuilder] is told which one to build.
class ItemCollection extends StatelessWidget {
  const ItemCollection({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  }) : sliver = false;

  /// Same as the default constructor, for use inside a [CustomScrollView].
  const ItemCollection.sliver({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  }) : sliver = true;

  final int itemCount;
  final Widget Function(BuildContext context, int index, bool grid) itemBuilder;
  final bool sliver;

  /// Room under the last item so the floating action button doesn't hide it.
  static const _bottomInset = 88.0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ViewMode>(
      valueListenable: ViewModeController.mode,
      builder: (context, mode, _) {
        final grid = mode == ViewMode.grid;
        if (sliver) {
          return grid
              ? SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s5,
                  ),
                  sliver: SliverGrid.builder(
                    gridDelegate: kItemGridDelegate,
                    itemCount: itemCount,
                    itemBuilder: (context, i) => itemBuilder(context, i, true),
                  ),
                )
              : SliverList.separated(
                  itemCount: itemCount,
                  separatorBuilder: (context, index) => const ItemRowDivider(),
                  itemBuilder: (context, i) => itemBuilder(context, i, false),
                );
        }
        return grid
            ? GridView.builder(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s5,
                  AppSpacing.s5,
                  AppSpacing.s5,
                  _bottomInset,
                ),
                gridDelegate: kItemGridDelegate,
                itemCount: itemCount,
                itemBuilder: (context, i) => itemBuilder(context, i, true),
              )
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: _bottomInset),
                itemCount: itemCount,
                separatorBuilder: (context, index) => const ItemRowDivider(),
                itemBuilder: (context, i) => itemBuilder(context, i, false),
              );
      },
    );
  }
}
