import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../services/sort_controller.dart';
import '../theme/app_spacing.dart';
import '../theme/theme_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.s5),
        children: [
          _SectionHeading('Appearance'),
          Card(
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeController.mode,
              builder: (context, mode, _) => Column(
                children: [
                  _SelectableOption(
                    icon: FluentIcons.phone_24_regular,
                    label: 'System default',
                    selected: mode == ThemeMode.system,
                    onTap: () => ThemeController.setMode(ThemeMode.system),
                  ),
                  const Divider(height: 1),
                  _SelectableOption(
                    icon: FluentIcons.weather_sunny_24_regular,
                    label: 'Light',
                    selected: mode == ThemeMode.light,
                    onTap: () => ThemeController.setMode(ThemeMode.light),
                  ),
                  const Divider(height: 1),
                  _SelectableOption(
                    icon: FluentIcons.weather_moon_24_regular,
                    label: 'Dark',
                    selected: mode == ThemeMode.dark,
                    onTap: () => ThemeController.setMode(ThemeMode.dark),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s7),
          _SectionHeading('General'),
          Card(
            child: ValueListenableBuilder<SortOrder>(
              valueListenable: SortController.order,
              builder: (context, order, _) => Column(
                children: [
                  _SelectableOption(
                    icon: FluentIcons.text_sort_ascending_24_regular,
                    label: 'Sort by name',
                    selected: order == SortOrder.name,
                    onTap: () => SortController.setOrder(SortOrder.name),
                  ),
                  const Divider(height: 1),
                  _SelectableOption(
                    icon: FluentIcons.calendar_ltr_24_regular,
                    label: 'Sort by date modified',
                    selected: order == SortOrder.dateNewest,
                    onTap: () => SortController.setOrder(SortOrder.dateNewest),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s7),
          _SectionHeading('About'),
          const Card(
            child: ListTile(
              leading: Icon(FluentIcons.info_24_regular),
              title: Text('Doc Manager'),
              subtitle: Text('Version 1.0.0'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.s2, bottom: AppSpacing.s3),
      child: Text(label, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

class _SelectableOption extends StatelessWidget {
  const _SelectableOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: selected
          ? Icon(
              FluentIcons.checkmark_circle_24_filled,
              color: Theme.of(context).colorScheme.primary,
            )
          : null,
      onTap: onTap,
    );
  }
}
