import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/app_lock_controller.dart';
import '../services/sort_controller.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import '../theme/app_spacing.dart';
import '../theme/theme_controller.dart';
import '../utils/format_bytes.dart';
import '../widgets/app_toast.dart';

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
          _SectionHeading('Privacy'),
          const Card(child: _PrivacyCard()),
          const SizedBox(height: AppSpacing.s7),
          _SectionHeading('Cloud backup'),
          const Card(child: _DriveSyncCard()),
          const SizedBox(height: AppSpacing.s7),
          _SectionHeading('Storage'),
          const Card(child: _StorageCard()),
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
              subtitle: Text('Version 1.0.5'),
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
      padding: const EdgeInsets.only(
        left: AppSpacing.s2,
        bottom: AppSpacing.s3,
      ),
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

  Future<void> _signIn() async {
    try {
      await SyncService.signIn();
      final email = SyncService.status.value.email;
      AppToast.success(
        email == null
            ? 'Google Drive connected'
            : 'Google Drive connected as $email',
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return;
      AppToast.error(e.description ?? e.code.name);
    } catch (e) {
      AppToast.error(e);
    }
  }

  Future<void> _signOut() async {
    try {
      await SyncService.signOut();
      AppToast.success('Google Drive disconnected');
    } catch (e) {
      AppToast.error(e);
    }
  }

  Future<void> _syncNow() async {
    await SyncService.syncNow();
    final status = SyncService.status.value;
    if (status.phase == SyncPhase.error) {
      AppToast.error(status.message ?? 'Sync failed');
    } else if (status.phase == SyncPhase.idle) {
      AppToast.success('Backup is up to date');
    }
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
              onTap: _signIn,
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
                  subtitle: syncing
                      ? _SyncProgress(status: status)
                      : Text(
                          error
                              ? status.message ?? 'Sync failed'
                              : _lastSyncedLabel(status.lastSynced),
                        ),
                  trailing: syncing
                      ? null
                      : IconButton(
                          tooltip: 'Sync now',
                          icon: const Icon(FluentIcons.arrow_sync_24_regular),
                          onPressed: _syncNow,
                        ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(FluentIcons.sign_out_24_regular),
                  title: const Text('Disconnect'),
                  subtitle: const Text(
                    'Files stay on this device and in Drive',
                  ),
                  onTap: _signOut,
                ),
              ],
            );
        }
      },
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  Future<void> _toggleLock(bool enabled) async {
    final error = await AppLockController.setLockEnabled(enabled);
    if (error != null) {
      AppToast.error(error);
    } else if (AppLockController.lockEnabled.value == enabled) {
      // Unchanged means the confirmation prompt was cancelled.
      AppToast.success(enabled ? 'App lock turned on' : 'App lock turned off');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: AppLockController.lockEnabled,
          builder: (context, enabled, _) => SwitchListTile(
            secondary: const Icon(FluentIcons.lock_closed_24_regular),
            title: const Text('App lock'),
            subtitle: const Text('Unlock with fingerprint, face or device PIN'),
            value: enabled,
            onChanged: _toggleLock,
          ),
        ),
        const Divider(height: 1),
        ValueListenableBuilder<bool>(
          valueListenable: AppLockController.hideInRecents,
          builder: (context, hide, _) => SwitchListTile(
            secondary: const Icon(FluentIcons.eye_off_24_regular),
            title: const Text('Hide in recent apps'),
            subtitle: const Text('Hide the app preview in the app switcher'),
            value: hide,
            onChanged: AppLockController.setHideInRecents,
          ),
        ),
      ],
    );
  }
}

/// "Uploading 3 of 12" with a progress bar while a sync runs.
class _SyncProgress extends StatelessWidget {
  const _SyncProgress({required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final total = status.toUpload;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          total == 0
              ? 'Checking for changes…'
              : 'Uploading ${status.uploaded + 1 > total ? total : status.uploaded + 1} of $total',
        ),
        const SizedBox(height: AppSpacing.s2),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.s1),
          child: LinearProgressIndicator(
            // Indeterminate until we know how much there is to upload.
            value: total == 0 ? null : status.uploaded / total,
            minHeight: 4,
          ),
        ),
      ],
    );
  }
}

/// Space used by documents on this phone, and by the backup and the whole
/// Google account in Drive.
class _StorageCard extends StatefulWidget {
  const _StorageCard();

  @override
  State<_StorageCard> createState() => _StorageCardState();
}

class _StorageCardState extends State<_StorageCard> {
  late final Future<({int bytes, int documents})> _phoneUsage =
      StorageService.usage();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FutureBuilder<({int bytes, int documents})>(
          future: _phoneUsage,
          builder: (context, snapshot) {
            final usage = snapshot.data;
            return ListTile(
              leading: const Icon(FluentIcons.phone_24_regular),
              title: const Text('On this phone'),
              subtitle: Text(
                usage == null
                    ? 'Calculating…'
                    : '${formatBytes(usage.bytes)} · ${usage.documents} '
                          '${usage.documents == 1 ? 'document' : 'documents'}',
              ),
            );
          },
        ),
        ValueListenableBuilder<SyncStatus>(
          valueListenable: SyncService.status,
          builder: (context, status, _) {
            final signedIn =
                status.phase == SyncPhase.idle ||
                status.phase == SyncPhase.syncing ||
                status.phase == SyncPhase.error;
            if (!signedIn || status.backupBytes == null) {
              return const SizedBox.shrink();
            }
            final used = status.driveUsedBytes;
            final limit = status.driveLimitBytes;
            return Column(
              children: [
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(FluentIcons.cloud_24_regular),
                  title: const Text('In Google Drive'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Backup: ${formatBytes(status.backupBytes!)}'),
                      if (used != null)
                        Text(
                          limit == null
                              ? 'Google account: ${formatBytes(used)} used'
                              : 'Google account: ${formatBytes(used)} of '
                                    '${formatBytes(limit)} used',
                        ),
                      if (used != null && limit != null && limit > 0) ...[
                        const SizedBox(height: AppSpacing.s2),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppSpacing.s1),
                          child: LinearProgressIndicator(
                            value: (used / limit).clamp(0, 1).toDouble(),
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
