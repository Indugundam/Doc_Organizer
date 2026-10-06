import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/search_index.dart';
import '../services/sort_controller.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/app_toast.dart';
import '../widgets/document_thumbnail.dart';
import '../widgets/folder_tile.dart';
import '../widgets/item_views.dart';
import '../widgets/reminders_action.dart';
import '../widgets/searchable_app_bar.dart';
import '../widgets/settings_action.dart';
import '../widgets/view_mode_action.dart';
import 'document_viewer_screen.dart';
import 'folder_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Directory> _folders = [];
  List<File> _allDocuments = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    SortController.order.addListener(_load);
    SearchIndex.revision.addListener(_onIndexChanged);
  }

  @override
  void dispose() {
    SortController.order.removeListener(_load);
    SearchIndex.revision.removeListener(_onIndexChanged);
    super.dispose();
  }

  List<Directory> get _filteredFolders {
    if (_query.isEmpty) return _folders;
    final query = _query.toLowerCase();
    return _folders
        .where((f) => p.basename(f.path).toLowerCase().contains(query))
        .toList();
  }

  /// Documents in any folder whose name or text matches the search.
  List<File> get _matchingDocuments {
    if (_query.trim().isEmpty) return const [];
    return _allDocuments.where((f) => SearchIndex.matches(f, _query)).toList();
  }

  /// More document text became searchable; refresh any active search.
  void _onIndexChanged() {
    if (_query.isNotEmpty && mounted) setState(() {});
  }

  Future<void> _load() async {
    final folders = await StorageService.listFolders();
    final documents = await StorageService.listAllDocuments();
    if (!mounted) return;
    setState(() {
      _folders = folders;
      _allDocuments = documents;
      _loading = false;
    });
  }

  void _onQueryChanged(String query) {
    final starting = _query.isEmpty && query.isNotEmpty;
    setState(() => _query = query);
    // Pick up documents added inside folders since the last load.
    if (starting) _load();
  }

  Future<void> _openDocument(File file) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => DocumentViewerScreen(file: file)),
    );
    await _load();
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

  Widget _buildFolderTile(Directory folder, bool grid) {
    return FolderTile(
      folder: folder,
      grid: grid,
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FolderScreen(folder: folder)),
        );
        await _load();
      },
      onMore: () => _openFolderMenu(folder),
    );
  }

  @override
  Widget build(BuildContext context) {
    final folders = _filteredFolders;
    return Scaffold(
      appBar: SearchableAppBar(
        title: 'Doc Manager',
        hintText: 'Search folders and documents',
        onQueryChanged: _onQueryChanged,
        actions: [
          viewModeAction(),
          remindersAction(context),
          settingsAction(context),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _folders.isEmpty
          ? _EmptyState(onCreateFolder: _createFolder)
          : _query.trim().isNotEmpty
          ? _SearchResults(
              query: _query,
              folders: folders,
              documents: _matchingDocuments,
              buildFolder: _buildFolderTile,
              onOpenDocument: _openDocument,
            )
          : ItemCollection(
              itemCount: folders.length,
              itemBuilder: (context, index, grid) =>
                  _buildFolderTile(folders[index], grid),
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

/// Search results across the whole app: matching folders, then matching
/// documents from any folder with an excerpt of where the text matched.
class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.query,
    required this.folders,
    required this.documents,
    required this.buildFolder,
    required this.onOpenDocument,
  });

  final String query;
  final List<Directory> folders;
  final List<File> documents;
  final Widget Function(Directory folder, bool grid) buildFolder;
  final ValueChanged<File> onOpenDocument;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final root = StorageService.cachedRootDir;
    return CustomScrollView(
      slivers: [
        // While documents are still being read, say so - otherwise a
        // missing result looks like a bug.
        ValueListenableBuilder<int>(
          valueListenable: SearchIndex.pending,
          builder: (context, pending, _) => SliverToBoxAdapter(
            child: pending == 0
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.s5,
                      AppSpacing.s4,
                      AppSpacing.s5,
                      0,
                    ),
                    child: Text(
                      'Reading text from $pending '
                      '${pending == 1 ? 'document' : 'documents'}…',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
          ),
        ),
        if (folders.isEmpty && documents.isEmpty)
          const SliverFillRemaining(hasScrollBody: false, child: _NoResults()),
        if (folders.isNotEmpty) ...[
          const _ResultsHeading('Folders'),
          ItemCollection.sliver(
            itemCount: folders.length,
            itemBuilder: (context, index, grid) =>
                buildFolder(folders[index], grid),
          ),
        ],
        if (documents.isNotEmpty) ...[
          const _ResultsHeading('Documents'),
          SliverList.builder(
            itemCount: documents.length,
            itemBuilder: (context, index) {
              final file = documents[index];
              final snippet = SearchIndex.snippet(file, query);
              final folderPath = root == null
                  ? ''
                  : p.relative(p.dirname(file.path), from: root.path);
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
                  p.basename(file.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  snippet ?? folderPath,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onOpenDocument(file),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.s7)),
        ],
      ],
    );
  }
}

class _ResultsHeading extends StatelessWidget {
  const _ResultsHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s5,
        AppSpacing.s5,
        AppSpacing.s5,
        AppSpacing.s2,
      ),
      sliver: SliverToBoxAdapter(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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
