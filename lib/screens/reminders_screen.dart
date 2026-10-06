import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/reminder_service.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/document_thumbnail.dart';
import '../widgets/reminder_dialog.dart';
import 'document_viewer_screen.dart';

/// Every document with an expiry/renewal reminder, soonest first, with
/// dates that have already passed listed separately at the bottom.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  List<(File, DocumentReminder)>? _items;

  @override
  void initState() {
    super.initState();
    _load();
    ReminderService.revision.addListener(_load);
  }

  @override
  void dispose() {
    ReminderService.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final items = await ReminderService.all();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _open(File file) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => DocumentViewerScreen(file: file)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final upcoming = items?.where((i) => !i.$2.isPast).toList() ?? [];
    final past = items?.where((i) => i.$2.isPast).toList().reversed ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? const _EmptyState()
          : ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.s7),
              children: [
                if (upcoming.isNotEmpty) const _Heading('Upcoming'),
                for (final (file, reminder) in upcoming)
                  _ReminderTile(
                    file: file,
                    reminder: reminder,
                    onTap: () => _open(file),
                    onEdit: () => editDocumentReminder(context, file),
                  ),
                if (past.isNotEmpty) const _Heading('Past'),
                for (final (file, reminder) in past)
                  _ReminderTile(
                    file: file,
                    reminder: reminder,
                    onTap: () => _open(file),
                    onEdit: () => editDocumentReminder(context, file),
                  ),
              ],
            ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s5,
        AppSpacing.s5,
        AppSpacing.s5,
        AppSpacing.s2,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.file,
    required this.reminder,
    required this.onTap,
    required this.onEdit,
  });

  final File file;
  final DocumentReminder reminder;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  /// "Today", "Tomorrow", "In 12 days", "3 days ago".
  String get _countdown {
    final days = reminder.daysLeft;
    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    if (days == -1) return 'Yesterday';
    return days > 0 ? 'In $days days' : '${-days} days ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final root = StorageService.cachedRootDir;
    final folder = root == null
        ? ''
        : p.relative(p.dirname(file.path), from: root.path);
    // Due within the notice period (or already passed): call it out.
    final urgent = reminder.daysLeft <= reminder.lead.days;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s5,
        vertical: AppSpacing.s1,
      ),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.s2),
        child: SizedBox.square(
          dimension: 48,
          child: DocumentThumbnail(file: file),
        ),
      ),
      title: Text(
        p.basenameWithoutExtension(file.path),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${reminder.summary} · $folder',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _countdown,
            style: theme.textTheme.bodySmall?.copyWith(
              color: urgent
                  ? AppColors.error500
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: urgent ? FontWeight.w600 : null,
            ),
          ),
          IconButton(
            tooltip: 'Edit reminder',
            icon: const Icon(FluentIcons.edit_24_regular, size: 20),
            onPressed: onEdit,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: AppColors.primary25,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                FluentIcons.calendar_clock_24_regular,
                size: 40,
                color: AppColors.primary700,
              ),
            ),
            const SizedBox(height: AppSpacing.s6),
            Text(
              'No reminders yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              'Open a document\'s menu and choose "Set reminder" to get '
              'notified before an insurance, warranty or passport expires.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
