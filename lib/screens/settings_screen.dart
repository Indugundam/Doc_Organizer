import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/sort_controller.dart';
import '../services/sync_service.dart';
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
          _SectionHeading('Cloud backup'),
          const Card(child: _DriveSyncCard()),
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
              subtitle: Text('Version 1.0.1'),
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

class _DriveSyncCard extends StatelessWidget {
  const _DriveSyncCard();

  Future<void> _signIn(BuildContext context) async {
    try {
      await SyncService.signIn();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return;
      if (context.mounted) _showError(context, e.description ?? e.code.name);
    } catch (e) {
      if (context.mounted) _showError(context, e.toString());
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _lastSyncedLabel(DateTime? time) {
    if (time == null) return 'Not synced yet';
    final ago = DateTime.now().difference(time);
    if (ago.inMinutes < 1) return 'Synced just now';
    if (ago.inHours < 1) return 'Synced ${ago.inMinutes} min ago';
    if (ago.inDays < 1) return 'Synced ${ago.inHours} h ago';
    return 'Synced ${time.day}/${time.month}/${time.year}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: SyncService.status,
      builder: (context, status, _) {
        switch (status.phase) {
          case SyncPhase.notConfigured:
            return const ListTile(
              leading: Icon(FluentIcons.cloud_off_24_regular),
              title: Text('Google Drive sync'),
              subtitle: Text('Not available in this build'),
            );
          case SyncPhase.signedOut:
            return ListTile(
              leading: const Icon(FluentIcons.cloud_24_regular),
              title: const Text('Connect Google Drive'),
              subtitle: Text(
                status.message ?? 'Back up your folders to Google Drive',
              ),
              onTap: () => _signIn(context),
            );
          case SyncPhase.idle:
          case SyncPhase.syncing:
          case SyncPhase.error:
            final syncing = status.phase == SyncPhase.syncing;
            final error = status.phase == SyncPhase.error;
            final colors = Theme.of(context).colorScheme;
            return Column(
              children: [
                ListTile(
                  leading: Icon(
                    error
                        ? FluentIcons.cloud_dismiss_24_regular
                        : syncing
                        ? FluentIcons.cloud_sync_24_regular
                        : FluentIcons.cloud_checkmark_24_regular,
                    color: error ? colors.error : null,
                  ),
                  title: Text(status.email ?? 'Google Drive'),
                  subtitle: Text(
                    syncing
                        ? 'Syncing…'
                        : error
                        ? status.message ?? 'Sync failed'
                        : _lastSyncedLabel(status.lastSynced),
                  ),
                  trailing: syncing
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          tooltip: 'Sync now',
                          icon: const Icon(FluentIcons.arrow_sync_24_regular),
                          onPressed: SyncService.syncNow,
                        ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(FluentIcons.sign_out_24_regular),
                  title: const Text('Disconnect'),
                  subtitle: const Text(
                    'Files stay on this device and in Drive',
                  ),
                  onTap: SyncService.signOut,
                ),
              ],
            );
        }
      },
    );
  }
}
