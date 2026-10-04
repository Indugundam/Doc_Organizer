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

import '../services/sort_controller.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/file_type_style.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/folder_tile.dart';
import '../widgets/searchable_app_bar.dart';
import '../widgets/settings_action.dart';
import '../widgets/video_thumbnail_preview.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
    SortController.order.addListener(_load);
  }

  @override
  void dispose() {
    SortController.order.removeListener(_load);
    super.dispose();
  }

  List<Directory> get _filteredSubfolders {
    if (_query.isEmpty) return _subfolders;
    final query = _query.toLowerCase();
    return _subfolders
        .where((f) => p.basename(f.path).toLowerCase().contains(query))
        .toList();
  }

  List<File> get _filteredDocuments {
    if (_query.isEmpty) return _documents;
    final query = _query.toLowerCase();
    return _documents
        .where((f) => p.basename(f.path).toLowerCase().contains(query))
        .toList();
  }

  Future<void> _load() async {
    final folders = await StorageService.listSubfolders(widget.folder);
    final docs = await StorageService.listDocuments(widget.folder);
    if (!mounted) return;
    setState(() {
      _subfolders = folders;
      _documents = docs;
      _loading = false;
    });
  }

  void _showError(Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
      await _load();
    } catch (e) {
      _showError(e);
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
      await _load();
    } catch (e) {
      _showError(e);
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
      await StorageService.deleteFolder(folder);
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
      await _load();
    } catch (e) {
      _showError(e);
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
      await _load();
    } catch (e) {
      _showError(e);
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
      await _load();
    } catch (e) {
      _showError(e);
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
      for (final asset in assets) {
        final file = await asset.originFile;
        if (file != null) {
          await StorageService.importFile(widget.folder, file.path);
        }
      }
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _importFile() async {
    try {
      final result = await FilePicker.pickFile();
      final path = result?.path;
      if (path == null) return;
      await StorageService.importFile(widget.folder, path);
      await _load();
    } catch (e) {
      _showError(e);
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

  Future<void> _shareDocument(File file) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          fileNameOverrides: [p.basename(file.path)],
        ),
      );
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _downloadDocument(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final saved = await FilePicker.saveFile(
        fileName: p.basename(file.path),
        bytes: bytes,
      );
      if (saved != null) _showMessage('Saved to device');
    } catch (e) {
      _showError(e);
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
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _deleteDocument(File file) async {
    final confirmed = await AppDialogs.confirmDelete(
      context,
      title: 'Delete document?',
      message: '"${p.basename(file.path)}" will be permanently deleted.',
    );
    if (confirmed == true) {
      await StorageService.deleteDocument(file);
      await _load();
    }
  }

  Future<void> _openDocumentMenu(File file) async {
    final choice = await AppDialogs.showActionSheet(
      context,
      actions: [
        const AppSheetAction(
          id: 'rename',
          icon: FluentIcons.rename_24_regular,
          label: 'Rename',
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
      case 'share':
        await _shareDocument(file);
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
    return Scaffold(
      appBar: SearchableAppBar(
        title: p.basename(widget.folder.path),
        hintText: 'Search this folder',
        onQueryChanged: (q) => setState(() => _query = q),
        actions: [settingsAction(context)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : isEmpty
          ? _EmptyState(onAdd: _openAddMenu)
          : noMatches
          ? const _NoResults()
          : CustomScrollView(
              slivers: [
                if (subfolders.isNotEmpty) ...[
                  const SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.s5,
                      AppSpacing.s5,
                      AppSpacing.s5,
                      AppSpacing.s2,
                    ),
                    sliver: SliverToBoxAdapter(child: _SectionLabel('Folders')),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s5,
                    ),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: AppSpacing.s4,
                            mainAxisSpacing: AppSpacing.s4,
                            childAspectRatio: 1.05,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final folder = subfolders[index];
                        return FolderTile(
                          folder: folder,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FolderScreen(folder: folder),
                              ),
                            );
                            await _load();
                          },
                          onMore: () => _openFolderMenu(folder),
                        );
                      }, childCount: subfolders.length),
                    ),
                  ),
                ],
                if (documents.isNotEmpty) ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.s5,
                      AppSpacing.s5,
                      AppSpacing.s5,
                      AppSpacing.s2,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _SectionLabel('Documents'),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.s5,
                      0,
                      AppSpacing.s5,
                      AppSpacing.s5,
                    ),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: AppSpacing.s3,
                            mainAxisSpacing: AppSpacing.s3,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final file = documents[index];
                        return _DocumentTile(
                          file: file,
                          onTap: () async {
                            final deleted = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    DocumentViewerScreen(file: file),
                              ),
                            );
                            if (deleted == true) await _load();
                          },
                          onMore: () => _openDocumentMenu(file),
                        );
                      }, childCount: documents.length),
                    ),
                  ),
                ],
              ],
            ),
      floatingActionButton: isEmpty
          ? null
          : FloatingActionButton(
              onPressed: _openAddMenu,
              child: const Icon(FluentIcons.add_24_regular),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              'Scan a document, add a photo or video, import\na file, or create a subfolder to get started.',
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
    required this.onTap,
    required this.onMore,
  });

  final File file;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final isImage = StorageService.isImage(file);
    final isVideo = StorageService.isVideo(file);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.s3),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: InkWell(
          onTap: onTap,
          onLongPress: onMore,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(AppSpacing.s3),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (isImage)
                  Image.file(file, fit: BoxFit.cover)
                else if (isVideo)
                  VideoThumbnailPreview(file: file)
                else
                  Builder(
                    builder: (context) {
                      final style = fileTypeStyleFor(file);
                      return Container(
                        color: style.background,
                        child: Center(
                          child: Icon(style.icon, size: 36, color: style.color),
                        ),
                      );
                    },
                  ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: IconButton(
                    onPressed: onMore,
                    icon: const Icon(
                      FluentIcons.more_vertical_24_regular,
                      size: 16,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s3,
                      vertical: AppSpacing.s2,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0),
                          Colors.black.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                    child: Text(
                      p.basename(file.path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
