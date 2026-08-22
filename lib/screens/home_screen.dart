import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_dialogs.dart';
import 'folder_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Directory> _folders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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
    final choice = await AppDialogs.showActionSheet(context, actions: [
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
    ]);
    if (choice == 'rename') await _renameFolder(folder);
    if (choice == 'delete') await _deleteFolder(folder);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Doc Manager')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _folders.isEmpty
              ? _EmptyState(onCreateFolder: _createFolder)
              : GridView.builder(
                  padding: const EdgeInsets.all(AppSpacing.s5),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: AppSpacing.s4,
                    mainAxisSpacing: AppSpacing.s4,
                    childAspectRatio: 1.05,
                  ),
                  itemCount: _folders.length,
                  itemBuilder: (context, index) {
                    final folder = _folders[index];
                    return _FolderTile(
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createFolder,
        icon: const Icon(FluentIcons.folder_add_24_regular),
        label: const Text('New folder'),
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
            Text('No folders yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.s2),
            Text(
              'Create a folder like "Bills" or "Hospital" to start\norganizing your documents.',
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

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.onTap,
    required this.onMore,
  });

  final Directory folder;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final count = folder.listSync().length;
    return Card(
      child: InkWell(
        onTap: onTap,
        onLongPress: onMore,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary25,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      FluentIcons.folder_24_filled,
                      color: AppColors.primary700,
                      size: 22,
                    ),
                  ),
                  IconButton(
                    onPressed: onMore,
                    icon: const Icon(FluentIcons.more_vertical_24_regular, size: 18),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                p.basename(folder.path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: AppSpacing.s1),
              Text(
                '$count item${count == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
