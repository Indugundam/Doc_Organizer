import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../services/reminder_service.dart';
import '../services/search_index.dart';
import '../services/sort_controller.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/format_bytes.dart';
import '../utils/format_date.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/app_toast.dart';
import '../widgets/breadcrumbs.dart';
import '../widgets/document_thumbnail.dart';
import '../widgets/folder_picker_sheet.dart';
import '../widgets/folder_tile.dart';
import '../widgets/item_views.dart';
import '../widgets/reminder_dialog.dart';
import '../widgets/reminders_action.dart';
import '../widgets/searchable_app_bar.dart';
import '../widgets/settings_action.dart';
import '../widgets/view_mode_action.dart';
import 'document_viewer_screen.dart';

class FolderScreen extends StatefulWidget {
  const FolderScreen({super.key, required this.folder});

  final Directory folder;

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  List<Directory> _subfolders = [];
  List<File> _documents = [];
  bool _loading = true;
  String _query = '';

  /// Paths of documents picked in multi-select mode (entered by
  /// long-pressing a document). Empty when not selecting.
  final Set<String> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
    SortController.order.addListener(_load);
    SearchIndex.revision.addListener(_onIndexChanged);
    ReminderService.revision.addListener(_onRemindersChanged);
  }

  @override
  void dispose() {
    SortController.order.removeListener(_load);
    SearchIndex.revision.removeListener(_onIndexChanged);
    ReminderService.revision.removeListener(_onRemindersChanged);
    super.dispose();
  }

  List<Directory> get _filteredSubfolders {
    if (_query.isEmpty) return _subfolders;
    final query = _query.toLowerCase();
    return _subfolders
        .where((f) => p.basename(f.path).toLowerCase().contains(query))
        .toList();
  }

  /// Matches file names and the text inside documents (see [SearchIndex]).
  List<File> get _filteredDocuments {
    if (_query.isEmpty) return _documents;
    return _documents.where((f) => SearchIndex.matches(f, _query)).toList();
  }

  /// More document text became searchable; refresh any active search.
  void _onIndexChanged() {
    if (_query.isNotEmpty && mounted) setState(() {});
  }

  /// A reminder was set or removed; refresh the dates shown on documents.
  void _onRemindersChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final folders = await StorageService.listSubfolders(widget.folder);
    final docs = await StorageService.listDocuments(widget.folder);
    if (!mounted) return;
    setState(() {
      _subfolders = folders;
      _documents = docs;
      _loading = false;
      // Drop selections for documents that no longer exist here.
      final paths = docs.map((d) => d.path).toSet();
      _selected.retainAll(paths);
    });
  }

  // --- Subfolders ---------------------------------------------------------

  Future<void> _createSubfolder() async {
    final name = await AppDialogs.promptForName(
      context,
      title: 'New subfolder',
      icon: FluentIcons.folder_add_24_regular,
      confirmLabel: 'Create',
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await StorageService.createSubfolder(widget.folder, name);
      AppToast.success('Folder "${name.trim()}" created');
      await _load();
    } catch (e) {
      AppToast.error(e);
    }
  }

  Future<void> _renameFolder(Directory folder) async {
    final current = p.basename(folder.path);
    final name = await AppDialogs.promptForName(
      context,
      title: 'Rename folder',
      icon: FluentIcons.rename_24_regular,
      initial: current,
      confirmLabel: 'Save',
    );
    if (name == null || name.trim().isEmpty || name == current) return;
    try {
      await StorageService.renameFolder(folder, name);
      AppToast.success('Folder renamed to "${name.trim()}"');
      await _load();
    } catch (e) {
      AppToast.error(e);
    }
  }

  Future<void> _deleteFolder(Directory folder) async {
    final confirmed = await AppDialogs.confirmDelete(
      context,
      title: 'Delete folder?',
      message:
          '"${p.basename(folder.path)}" and everything inside it will be permanently deleted.',
    );
    if (confirmed == true) {
      try {
        await StorageService.deleteFolder(folder);
        AppToast.success('Folder deleted');
      } catch (e) {
        AppToast.error(e);
      }
      await _load();
    }
  }

  Future<void> _openFolderMenu(Directory folder) async {
    final choice = await AppDialogs.showActionSheet(
      context,
      actions: [
        const AppSheetAction(
          id: 'rename',
          icon: FluentIcons.rename_24_regular,
          label: 'Rename',
        ),
        const AppSheetAction(
          id: 'delete',
          icon: FluentIcons.delete_24_regular,
          label: 'Delete',
          destructive: true,
        ),
      ],
    );
    if (choice == 'rename') await _renameFolder(folder);
    if (choice == 'delete') await _deleteFolder(folder);
  }

  // --- Adding documents ----------------------------------------------------

  /// Captures a photo with the camera and lets the user crop it. Returns the
  /// cropped image path, or null if the user cancelled at any step.
  Future<String?> _captureAndCropPage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (picked == null) return null;

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 90,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Scan document',
          toolbarColor: AppColors.neutral0,
          toolbarWidgetColor: AppColors.neutral1300,
          activeControlsWidgetColor: AppColors.primary500,
          statusBarLight: true,
          lockAspectRatio: false,
        ),
        IOSUiSettings(title: 'Scan document'),
      ],
    );
    return cropped?.path ?? picked.path;
  }

  Future<void> _scanDocument() async {
    try {
      final resultPath = await _captureAndCropPage();
      if (resultPath == null) return;
      await StorageService.importFile(widget.folder, resultPath);
      AppToast.success('Document scanned');
      await _load();
    } catch (e) {
      AppToast.error(e);
    }
  }

  /// Scans one or more pages in a row and combines them into a single
  /// multi-page PDF, the way a dedicated document-scanning app would.
  Future<void> _scanToPdf() async {
    final pages = <String>[];
    try {
      while (true) {
        final path = await _captureAndCropPage();
        if (path == null) break;
        pages.add(path);
        if (!mounted) break;

        final choice = await AppDialogs.showActionSheet(
          context,
          actions: [
            const AppSheetAction(
              id: 'more',
              icon: FluentIcons.scan_camera_24_regular,
              label: 'Scan another page',
            ),
            AppSheetAction(
              id: 'done',
              icon: FluentIcons.document_pdf_24_regular,
              label:
                  'Save PDF (${pages.length} page${pages.length == 1 ? '' : 's'})',
            ),
            const AppSheetAction(
              id: 'cancel',
              icon: FluentIcons.delete_24_regular,
              label: 'Discard scan',
              destructive: true,
            ),
          ],
        );

        if (choice == 'cancel') {
          pages.clear();
          break;
        }
        if (choice != 'more') break;
      }

      if (pages.isEmpty) return;

      final bytes = await _buildPdfBytes(pages);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await StorageService.saveBytes(widget.folder, 'Scan_$stamp.pdf', bytes);
      AppToast.success(
        'PDF saved (${pages.length} page${pages.length == 1 ? '' : 's'})',
      );
      await _load();
    } catch (e) {
      AppToast.error(e);
    }
  }

  Future<Uint8List> _buildPdfBytes(List<String> imagePaths) async {
    final doc = pw.Document();
    for (final path in imagePaths) {
      final bytes = await File(path).readAsBytes();
      final image = pw.MemoryImage(bytes);
      doc.addPage(
        pw.Page(
          build: (ctx) =>
              pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ),
      );
    }
    return doc.save();
  }

  Future<void> _recordVideo() async {
    try {
      final picked = await ImagePicker().pickVideo(source: ImageSource.camera);
      if (picked == null) return;
      await StorageService.importFile(widget.folder, picked.path);
      AppToast.success('Video saved');
      await _load();
    } catch (e) {
      AppToast.error(e);
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final assets = await AssetPicker.pickAssets(
        context,
        pickerConfig: const AssetPickerConfig(
          requestType: RequestType.common,
          maxAssets: 20,
        ),
      );
      if (assets == null || assets.isEmpty) return;
      var added = 0;
      for (final asset in assets) {
        final file = await asset.originFile;
        if (file != null) {
          await StorageService.importFile(widget.folder, file.path);
          added++;
        }
      }
      if (added == assets.length) {
        AppToast.success('Added $added item${added == 1 ? '' : 's'}');
      } else {
        AppToast.warning(
          'Added $added of ${assets.length} items. '
          'Some could not be read from the gallery.',
        );
      }
      await _load();
    } catch (e) {
      AppToast.error(e);
    }
  }

  Future<void> _importFile() async {
    try {
      final result = await FilePicker.pickFile();
      final path = result?.path;
      if (path == null) return;
      await StorageService.importFile(widget.folder, path);
      AppToast.success('File imported');
      await _load();
    } catch (e) {
      AppToast.error(e);
    }
  }

  Future<void> _openAddMenu() async {
    final choice = await AppDialogs.showActionSheet(
      context,
      actions: const [
        AppSheetAction(
          id: 'scan',
          icon: FluentIcons.scan_camera_24_regular,
          label: 'Scan a document',
        ),
        AppSheetAction(
          id: 'scan_pdf',
          icon: FluentIcons.document_pdf_24_regular,
          label: 'Scan to PDF (multi-page)',
        ),
        AppSheetAction(
          id: 'video',
          icon: FluentIcons.video_24_regular,
          label: 'Record a video',
        ),
        AppSheetAction(
          id: 'gallery',
          icon: FluentIcons.image_24_regular,
          label: 'Choose from Gallery',
        ),
        AppSheetAction(
          id: 'file',
          icon: FluentIcons.arrow_upload_24_regular,
          label: 'Import a file',
        ),
        AppSheetAction(
          id: 'folder',
          icon: FluentIcons.folder_add_24_regular,
          label: 'New subfolder',
        ),
      ],
    );
    switch (choice) {
      case 'scan':
        await _scanDocument();
      case 'scan_pdf':
        await _scanToPdf();
      case 'video':
        await _recordVideo();
      case 'gallery':
        await _pickFromGallery();
      case 'file':
        await _importFile();
      case 'folder':
        await _createSubfolder();
    }
  }

  // --- Documents -----------------------------------------------------------

  Future<void> _shareDocuments(List<File> files) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [for (final f in files) XFile(f.path)],
          fileNameOverrides: [for (final f in files) p.basename(f.path)],
        ),
      );
    } catch (e) {
      AppToast.error(e);
    }
  }

  Future<void> _moveDocuments(List<File> files) async {
    final target = await showFolderPicker(
      context,
      title: files.length == 1
          ? 'Move to folder'
          : 'Move ${files.length} documents to folder',
      current: widget.folder,
    );
    if (target == null) return;
    var moved = 0;
    try {
      for (final file in files) {
        await StorageService.moveDocument(file, target);
        moved++;
      }
      AppToast.success(
        'Moved ${moved == 1 ? 'document' : '$moved documents'} '
        'to "${p.basename(target.path)}"',
      );
    } catch (e) {
      AppToast.error(e);
    }
    _clearSelection();
    await _load();
  }

  Future<void> _deleteDocuments(List<File> files) async {
    final confirmed = await AppDialogs.confirmDelete(
      context,
      title: 'Delete ${files.length} documents?',
      message: 'The selected documents will be permanently deleted.',
    );
    if (confirmed != true) return;
    try {
      for (final file in files) {
        await StorageService.deleteDocument(file);
      }
      AppToast.success(
        files.length == 1
            ? 'Document deleted'
            : '${files.length} documents deleted',
      );
    } catch (e) {
      AppToast.error(e);
    }
    _clearSelection();
    await _load();
  }

  // --- Multi-select ----------------------------------------------------------

  List<File> get _selectedDocuments =>
      _documents.where((d) => _selected.contains(d.path)).toList();

  void _toggleSelected(File file) {
    setState(() {
      if (!_selected.remove(file.path)) _selected.add(file.path);
    });
  }

  void _clearSelection() {
    if (_selected.isEmpty || !mounted) return;
    setState(_selected.clear);
  }

  void _selectAllVisible() {
    setState(() => _selected.addAll(_filteredDocuments.map((d) => d.path)));
  }

  PreferredSizeWidget _buildSelectionBar() {
    final files = _selectedDocuments;
    final allSelected = _filteredDocuments.every(
      (d) => _selected.contains(d.path),
    );
    return AppBar(
      leading: IconButton(
        tooltip: 'Cancel',
        icon: const Icon(FluentIcons.dismiss_24_regular),
        onPressed: _clearSelection,
      ),
      title: Text('${files.length} selected'),
      actions: [
        if (!allSelected)
          IconButton(
            tooltip: 'Select all',
            icon: const Icon(FluentIcons.select_all_on_24_regular),
            onPressed: _selectAllVisible,
          ),
        IconButton(
          tooltip: 'Move',
          icon: const Icon(FluentIcons.folder_arrow_right_24_regular),
          onPressed: () => _moveDocuments(files),
        ),
        IconButton(
          tooltip: 'Share',
          icon: const Icon(FluentIcons.share_24_regular),
          onPressed: () => _shareDocuments(files),
        ),
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(FluentIcons.delete_24_regular),
          onPressed: () => _deleteDocuments(files),
        ),
      ],
    );
  }

  Future<void> _downloadDocument(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final saved = await FilePicker.saveFile(
        fileName: p.basename(file.path),
        bytes: bytes,
      );
      if (saved != null) AppToast.success('Saved to device');
    } catch (e) {
      AppToast.error(e);
    }
  }

  Future<void> _renameDocument(File file) async {
    final current = p.basenameWithoutExtension(file.path);
    final name = await AppDialogs.promptForName(
      context,
      title: 'Rename document',
      icon: FluentIcons.rename_24_regular,
      initial: current,
      confirmLabel: 'Save',
    );
    if (name == null || name.trim().isEmpty || name == current) return;
    try {
      await StorageService.renameDocument(file, name);
      AppToast.success('Document renamed');
      await _load();
    } catch (e) {
      AppToast.error(e);
    }
  }

  Future<void> _deleteDocument(File file) async {
    final confirmed = await AppDialogs.confirmDelete(
      context,
      title: 'Delete document?',
      message: '"${p.basename(file.path)}" will be permanently deleted.',
    );
    if (confirmed == true) {
      try {
        await StorageService.deleteDocument(file);
        AppToast.success('Document deleted');
      } catch (e) {
        AppToast.error(e);
      }
      await _load();
    }
  }

  Future<void> _openDocumentMenu(File file) async {
    final hasReminder = ReminderService.reminderFor(file) != null;
    final choice = await AppDialogs.showActionSheet(
      context,
      actions: [
        const AppSheetAction(
          id: 'rename',
          icon: FluentIcons.rename_24_regular,
          label: 'Rename',
        ),
        AppSheetAction(
          id: 'reminder',
          icon: FluentIcons.calendar_clock_24_regular,
          label: hasReminder ? 'Edit reminder' : 'Set reminder',
        ),
        const AppSheetAction(
          id: 'move',
          icon: FluentIcons.folder_arrow_right_24_regular,
          label: 'Move',
        ),
        const AppSheetAction(
          id: 'share',
          icon: FluentIcons.share_24_regular,
          label: 'Share',
        ),
        const AppSheetAction(
          id: 'download',
          icon: FluentIcons.arrow_download_24_regular,
          label: 'Download',
        ),
        const AppSheetAction(
          id: 'delete',
          icon: FluentIcons.delete_24_regular,
          label: 'Delete',
          destructive: true,
        ),
      ],
    );
    switch (choice) {
      case 'rename':
        await _renameDocument(file);
      case 'reminder':
        if (mounted) await editDocumentReminder(context, file);
      case 'move':
        await _moveDocuments([file]);
      case 'share':
        await _shareDocuments([file]);
      case 'download':
        await _downloadDocument(file);
      case 'delete':
        await _deleteDocument(file);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = _subfolders.isEmpty && _documents.isEmpty;
    final subfolders = _filteredSubfolders;
    final documents = _filteredDocuments;
    final noMatches =
        _query.isNotEmpty && subfolders.isEmpty && documents.isEmpty;
    // Back exits multi-select instead of leaving the folder.
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          // IndexedStack keeps the search bar (and any typed query) alive
          // while the selection bar is showing.
          child: IndexedStack(
            index: _selecting ? 1 : 0,
            children: [
              SearchableAppBar(
                title: p.basename(widget.folder.path),
                hintText: 'Search this folder',
                onQueryChanged: (q) => setState(() => _query = q),
                actions: [
                  viewModeAction(),
                  remindersAction(context),
                  settingsAction(context),
                ],
              ),
              _buildSelectionBar(),
            ],
          ),
        ),
        body: Column(
          children: [
            // Inert while selecting, like the folders below it.
            IgnorePointer(
              ignoring: _selecting,
              child: Breadcrumbs(
                folder: widget.folder,
                onNavigate: (levelsUp) {
                  var remaining = levelsUp;
                  Navigator.popUntil(context, (_) => remaining-- <= 0);
                },
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : isEmpty
                  ? _EmptyState(onAdd: _openAddMenu)
                  : noMatches
                  ? const _NoResults()
                  : ItemCollection(
                      // Folders first, then documents, in one list or grid.
                      itemCount: subfolders.length + documents.length,
                      itemBuilder: (context, index, grid) {
                        if (index < subfolders.length) {
                          final folder = subfolders[index];
                          // Folders are dimmed and inert while selecting
                          // documents.
                          return IgnorePointer(
                            ignoring: _selecting,
                            child: AnimatedOpacity(
                              opacity: _selecting ? 0.4 : 1,
                              duration: const Duration(milliseconds: 150),
                              child: FolderTile(
                                folder: folder,
                                grid: grid,
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          FolderScreen(folder: folder),
                                    ),
                                  );
                                  await _load();
                                },
                                onMore: () => _openFolderMenu(folder),
                              ),
                            ),
                          );
                        }
                        final file = documents[index - subfolders.length];
                        return _DocumentTile(
                          file: file,
                          grid: grid,
                          selecting: _selecting,
                          selected: _selected.contains(file.path),
                          onTap: () async {
                            if (_selecting) return _toggleSelected(file);
                            final deleted = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    DocumentViewerScreen(file: file),
                              ),
                            );
                            if (deleted == true) await _load();
                          },
                          onLongPress: () => _toggleSelected(file),
                          onMore: () => _openDocumentMenu(file),
                        );
                      },
                    ),
            ),
          ],
        ),
        floatingActionButton: isEmpty || _selecting
            ? null
            : FloatingActionButton(
                onPressed: _openAddMenu,
                child: const Icon(FluentIcons.add_24_regular),
              ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No matches found',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

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
                FluentIcons.document_add_24_regular,
                size: 40,
                color: AppColors.primary700,
              ),
            ),
            const SizedBox(height: AppSpacing.s6),
            Text(
              'Nothing here yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              'Scan a document, add a photo or video, import a file, or create a subfolder to get started.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.s7),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(FluentIcons.add_24_regular, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.file,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
    required this.grid,
  });

  final File file;

  /// Multi-select mode is on: taps toggle selection and the menu button is
  /// replaced by a selection indicator.
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;

  /// Show as an [ItemCard] instead of an [ItemRow].
  final bool grid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stat = file.statSync();
    final title = p.basename(file.path);
    final reminder = ReminderService.reminderFor(file);
    final subtitle = reminder == null
        ? formatBytes(stat.size)
        : '${formatBytes(stat.size)} · ${reminder.summary}';
    final date = formatDate(stat.modified);
    final trailing = selecting
        ? Icon(
            selected
                ? FluentIcons.checkmark_circle_24_filled
                : FluentIcons.circle_24_regular,
            size: 22,
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          )
        : IconButton(
            onPressed: onMore,
            icon: const Icon(FluentIcons.more_vertical_24_regular, size: 18),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          );
    if (grid) {
      return ItemCard(
        preview: DocumentThumbnail(file: file),
        title: title,
        subtitle: subtitle,
        date: date,
        selected: selected,
        onTap: onTap,
        onLongPress: onLongPress,
        trailing: trailing,
      );
    }
    return ItemRow(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.s3),
        child: Container(
          width: 44,
          height: kItemRowLeadingWidth,
          foregroundDecoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outline),
            borderRadius: BorderRadius.circular(AppSpacing.s3),
          ),
          child: DocumentThumbnail(file: file),
        ),
      ),
      title: title,
      subtitle: subtitle,
      date: date,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      trailing: trailing,
    );
  }
}
