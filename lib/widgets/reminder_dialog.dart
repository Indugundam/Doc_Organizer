import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/reminder_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/format_date.dart';
import 'app_dialogs.dart';
import 'app_toast.dart';

/// Lets the user set, change or remove the expiry/renewal reminder on
/// [file], then saves it and confirms with a snack bar.
Future<void> editDocumentReminder(BuildContext context, File file) async {
  final existing = ReminderService.reminderFor(file);
  final result = await showDialog<_ReminderResult>(
    context: context,
    builder: (_) => _ReminderDialog(file: file, existing: existing),
  );
  if (result == null) return;

  if (result.remove) {
    await ReminderService.removeReminder(file);
    AppToast.success('Reminder removed');
    return;
  }
  try {
    final allowed = await ReminderService.setReminder(
      file,
      date: result.date!,
      kind: result.kind,
      lead: result.lead,
    );
    if (allowed) {
      AppToast.success('Reminder set for ${formatDate(result.date!)}');
    } else {
      AppToast.warning(
        'Reminder saved, but notifications are off for Doc Manager. '
        'Turn them on in system settings to be alerted.',
      );
    }
  } catch (e) {
    AppToast.error(e);
  }
}

class _ReminderResult {
  const _ReminderResult.save(this.date, this.kind, this.lead) : remove = false;
  const _ReminderResult.remove()
    : date = null,
      kind = ReminderKind.expiry,
      lead = ReminderLead.onTheDay,
      remove = true;

  final DateTime? date;
  final ReminderKind kind;
  final ReminderLead lead;
  final bool remove;
}

class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog({required this.file, required this.existing});

  final File file;
  final DocumentReminder? existing;

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  late ReminderKind _kind = widget.existing?.kind ?? ReminderKind.expiry;
  late ReminderLead _lead = widget.existing?.lead ?? ReminderLead.oneWeek;

  /// Null until a date is picked. A past reminder's date isn't carried over
  /// since only future dates are allowed.
  late DateTime? _date = widget.existing?.isPast == false
      ? widget.existing!.date
      : null;

  Future<void> _pickDate() async {
    final today = ReminderService.today();
    final first = DateTime(today.year, today.month, today.day + 1);
    final picked = await showDatePicker(
      context: context,
      helpText: _kind == ReminderKind.expiry ? 'Expiry date' : 'Renewal date',
      initialDate: _date ?? first,
      // Only future dates: tomorrow onwards.
      firstDate: first,
      lastDate: DateTime(first.year + 50),
    );
    if (picked == null) return;
    setState(() {
      _date = picked;
      // A short notice period still fits if the chosen one no longer does.
      if (!ReminderService.leadAvailable(picked, _lead)) {
        _lead = ReminderLead.values.lastWhere(
          (l) =>
              l.days < _lead.days && ReminderService.leadAvailable(picked, l),
          orElse: () => ReminderLead.onTheDay,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final date = _date;
    return AlertDialog(
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
          const AppDialogIcon(icon: FluentIcons.calendar_clock_24_regular),
          const SizedBox(width: AppSpacing.s4),
          Expanded(
            child: Text(
              widget.existing == null ? 'Set reminder' : 'Edit reminder',
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              p.basename(widget.file.path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: secondary,
            ),
            const SizedBox(height: AppSpacing.s5),
            SegmentedButton<ReminderKind>(
              segments: const [
                ButtonSegment(
                  value: ReminderKind.expiry,
                  label: Text('Expiry'),
                ),
                ButtonSegment(
                  value: ReminderKind.renewal,
                  label: Text('Renewal'),
                ),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: AppSpacing.s5),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(AppRadius.medium),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: _kind == ReminderKind.expiry
                      ? 'Expiry date'
                      : 'Renewal date',
                  suffixIcon: const Icon(FluentIcons.calendar_24_regular),
                ),
                isEmpty: date == null,
                child: date == null ? null : Text(formatDate(date)),
              ),
            ),
            const SizedBox(height: AppSpacing.s5),
            Text('Notify me', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.s3),
            Wrap(
              spacing: AppSpacing.s3,
              runSpacing: AppSpacing.s3,
              children: [
                for (final lead in ReminderLead.values)
                  ChoiceChip(
                    label: Text(lead.label),
                    selected: _lead == lead,
                    // Notice periods that would already have passed for
                    // the chosen date can't be picked.
                    onSelected:
                        date == null ||
                            ReminderService.leadAvailable(date, lead)
                        ? (_) => setState(() => _lead = lead)
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              _lead == ReminderLead.onTheDay
                  ? 'You\'ll be notified at ${ReminderService.notifyHour}:00 AM '
                        'on the day.'
                  : 'You\'ll be notified at ${ReminderService.notifyHour}:00 AM '
                        '${_lead.label.toLowerCase()} and again on the day.',
              style: secondary,
            ),
          ],
        ),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error500),
            onPressed: () =>
                Navigator.pop(context, const _ReminderResult.remove()),
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: date == null
              ? null
              : () => Navigator.pop(
                  context,
                  _ReminderResult.save(date, _kind, _lead),
                ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
