import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../services/reminder_service.dart';
import '../services/storage_service.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../utils/file_type_style.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/app_toast.dart';
import '../widgets/reminder_dialog.dart';
import '../widgets/reminders_action.dart';
import '../widgets/settings_action.dart';

class DocumentViewerScreen extends StatefulWidget {
  const DocumentViewerScreen({super.key, required this.file});

  final File file;

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  @override
  void initState() {
    super.initState();
    ReminderService.revision.addListener(_onRemindersChanged);
  }

  @override
  void dispose() {
    ReminderService.revision.removeListener(_onRemindersChanged);
    super.dispose();
  }

  void _onRemindersChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(widget.file.path)],
          fileNameOverrides: [p.basename(widget.file.path)],
        ),
      );
    } catch (e) {
      AppToast.error(e);
    }
  }

  Future<void> _download() async {
    try {
      final bytes = await widget.file.readAsBytes();
      final saved = await FilePicker.saveFile(
        fileName: p.basename(widget.file.path),
        bytes: bytes,
      );
      if (saved != null) AppToast.success('Saved to device');
    } catch (e) {
      AppToast.error(e);
    }
  }

  Future<void> _delete() async {
    final confirmed = await AppDialogs.confirmDelete(
      context,
      title: 'Delete document?',
      message: '"${p.basename(widget.file.path)}" will be permanently deleted.',
    );
    if (confirmed == true) {
      try {
        await StorageService.deleteDocument(widget.file);
      } catch (e) {
        AppToast.error(e);
        return;
      }
      // Popped first: leaving the page would hide a toast shown here.
      if (mounted) Navigator.pop(context, true);
      AppToast.success('Document deleted');
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final isImage = StorageService.isImage(file);
    final isVideo = StorageService.isVideo(file);

    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text(p.basename(file.path), overflow: TextOverflow.ellipsis),
        actions: [
          Builder(
            builder: (context) {
              final reminder = ReminderService.reminderFor(file);
              return IconButton(
                icon: Icon(
                  reminder == null
                      ? FluentIcons.calendar_clock_24_regular
                      : FluentIcons.calendar_clock_24_filled,
                ),
                onPressed: () => editDocumentReminder(context, file),
                tooltip: reminder == null
                    ? 'Set reminder'
                    : 'Reminder: ${reminder.summary}',
              );
            },
          ),
          IconButton(
            icon: const Icon(FluentIcons.share_24_regular),
            onPressed: _share,
            tooltip: 'Share',
          ),
          IconButton(
            icon: const Icon(FluentIcons.arrow_download_24_regular),
            onPressed: _download,
            tooltip: 'Download',
          ),
          IconButton(
            icon: const Icon(FluentIcons.delete_24_regular),
            onPressed: _delete,
            tooltip: 'Delete',
          ),
          remindersAction(context),
          settingsAction(context),
          const SizedBox(width: AppSpacing.s2),
        ],
      ),
      body: isImage
          ? Center(child: InteractiveViewer(child: Image.file(file)))
          : isVideo
              ? _VideoPlayerView(file: file)
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.s7),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Builder(
                          builder: (context) {
                            final style = fileTypeStyleFor(file);
                            return Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                color: style.background,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(style.icon, size: 44, color: style.color),
                            );
                          },
                        ),
                        const SizedBox(height: AppSpacing.s6),
                        Text(
                          p.basename(file.path),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.s7),
                        FilledButton.icon(
                          icon: const Icon(FluentIcons.open_24_regular, size: 18),
                          label: const Text('Open with...'),
                          onPressed: () => OpenFilex.open(file.path),
                        ),
                      ],
                    ),
                  ),
                ),
    );

    // Image/video always get the dark viewer chrome, independent of the
    // app's light/dark setting - defined once in AppTheme.mediaViewer.
    return (isImage || isVideo)
        ? Theme(data: AppTheme.mediaViewer, child: scaffold)
        : scaffold;
  }
}

class _VideoPlayerView extends StatefulWidget {
  const _VideoPlayerView({required this.file});

  final File file;

  @override
  State<_VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<_VideoPlayerView> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
      }).catchError((e) {
        if (!mounted) return;
        setState(() => _error = e.toString());
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text(
          'Could not play this video.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_controller),
            _VideoControls(controller: _controller),
          ],
        ),
      ),
    );
  }
}

class _VideoControls extends StatefulWidget {
  const _VideoControls({required this.controller});

  final VideoPlayerController controller;

  @override
  State<_VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<_VideoControls> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final playing = widget.controller.value.isPlaying;
    return GestureDetector(
      onTap: () {
        setState(() {
          playing ? widget.controller.pause() : widget.controller.play();
        });
      },
      child: AnimatedOpacity(
        opacity: playing ? 0 : 1,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            FluentIcons.play_24_filled,
            color: Colors.white,
            size: 30,
          ),
        ),
      ),
    );
  }
}
