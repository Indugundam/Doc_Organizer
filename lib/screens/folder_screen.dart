import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_dialogs.dart';
import 'document_viewer_screen.dart';

class FolderScreen extends StatefulWidget {
  const FolderScreen({super.key, required this.folder});

  final Directory folder;

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  List<File> _documents = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final docs = await StorageService.listDocuments(widget.folder);
    if (!mounted) return;
    setState(() {
      _documents = docs;
      _loading = false;
    });
  }

  void _showError(Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
    );
  }

  Future<void> _scanDocument() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      if (picked == null) return;

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
      final resultPath = cropped?.path ?? picked.path;
      await StorageService.importFile(widget.folder, resultPath);
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      await StorageService.importFile(widget.folder, picked.path);
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
    final choice = await AppDialogs.showActionSheet(context, actions: const [
      AppSheetAction(
        id: 'scan',
        icon: FluentIcons.scan_camera_24_regular,
        label: 'Scan with camera',
      ),
      AppSheetAction(
        id: 'gallery',
        icon: FluentIcons.image_24_regular,
        label: 'Choose photo from gallery',
      ),
      AppSheetAction(
        id: 'file',
        icon: FluentIcons.arrow_upload_24_regular,
        label: 'Import a file (PDF, etc.)',
      ),
    ]);
    switch (choice) {
      case 'scan':
        await _scanDocument();
      case 'gallery':
        await _pickFromGallery();
      case 'file':
        await _importFile();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(p.basename(widget.folder.path))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _documents.isEmpty
              ? _EmptyState(onAdd: _openAddMenu)
              : GridView.builder(
                  padding: const EdgeInsets.all(AppSpacing.s5),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: AppSpacing.s3,
                    mainAxisSpacing: AppSpacing.s3,
                  ),
                  itemCount: _documents.length,
                  itemBuilder: (context, index) {
                    final file = _documents[index];
                    return _DocumentTile(
                      file: file,
                      onTap: () async {
                        final deleted = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DocumentViewerScreen(file: file),
                          ),
                        );
                        if (deleted == true) await _load();
                      },
                      onDelete: () => _deleteDocument(file),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddMenu,
        child: const Icon(FluentIcons.add_24_regular),
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
            Text('No documents yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.s2),
            Text(
              'Scan a document, add a photo, or import\na file to get started.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.s7),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(FluentIcons.add_24_regular, size: 18),
              label: const Text('Add document'),
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
    required this.onDelete,
  });

  final File file;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isImage = StorageService.isImage(file);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.s3),
      child: Material(
        color: AppColors.neutral0,
        child: InkWell(
          onTap: onTap,
          onLongPress: onDelete,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.neutral100),
              borderRadius: BorderRadius.circular(AppSpacing.s3),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                isImage
                    ? Image.file(file, fit: BoxFit.cover)
                    : Container(
                        color: AppColors.primary25,
                        child: const Center(
                          child: Icon(
                            FluentIcons.document_24_filled,
                            size: 36,
                            color: AppColors.primary700,
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
