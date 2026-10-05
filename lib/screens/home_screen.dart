import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/sort_controller.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/folder_tile.dart';
import '../widgets/searchable_app_bar.dart';
import '../widgets/settings_action.dart';
import 'folder_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Directory> _folders = [];
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

  List<Directory> get _filteredFolders {
    if (_query.isEmpty) return _folders;
    final query = _query.toLowerCase();
    return _folders
        .where((f) => p.basename(f.path).toLowerCase().contains(query))
        .toList();
  }

  Future<void> _load() async {
    final folders = await StorageService.listFolders();
    if (!mounted) return;
    setState(() {
      _folders = folders;
      _loading = false;
    });
  }

  void _showError(Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
    );
  }

  Future<void> _createFolder() async {
    final name = await AppDialogs.promptForName(
      context,
      title: 'New folder',
      icon: FluentIcons.folder_add_24_regular,
      confirmLabel: 'Create',
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await StorageService.createFolder(name);
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

  @override
  Widget build(BuildContext context) {
    final folders = _filteredFolders;
    return Scaffold(
      appBar: SearchableAppBar(
        title: 'Doc Manager',
        hintText: 'Search folders',
        onQueryChanged: (q) => setState(() => _query = q),
        actions: [settingsAction(context)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _folders.isEmpty
          ? _EmptyState(onCreateFolder: _createFolder)
          : folders.isEmpty
          ? const _NoResults()
          : GridView.builder(
              padding: const EdgeInsets.all(AppSpacing.s5),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: AppSpacing.s4,
                mainAxisSpacing: AppSpacing.s4,
                childAspectRatio: 1.05,
              ),
              itemCount: folders.length,
              itemBuilder: (context, index) {
                final folder = folders[index];
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
              },
            ),
      floatingActionButton: _folders.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _createFolder,
              icon: const Icon(FluentIcons.folder_add_24_regular),
              label: const Text('New folder'),
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
  const _EmptyState({required this.onCreateFolder});

  final VoidCallback onCreateFolder;

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
                FluentIcons.folder_add_24_regular,
                size: 40,
                color: AppColors.primary700,
              ),
            ),
            const SizedBox(height: AppSpacing.s6),
            Text(
              'No folders yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              'Create a folder like "Bills" or "Hospital" to start organizing your documents.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.s7),
            FilledButton.icon(
              onPressed: onCreateFolder,
              icon: const Icon(FluentIcons.add_24_regular, size: 18),
              label: const Text('Create folder'),
            ),
          ],
        ),
      ),
    );
  }
}
