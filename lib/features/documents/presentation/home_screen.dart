import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/document_repository.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  var _query = '';
  var _grid = true;
  var _favoritesOnly = false;
  var _sort = DocumentSort.recentlyEdited;
  String? _folderId;

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(
      documentsProvider(
        DocumentQuery(
          search: _query,
          folderId: _folderId,
          favoritesOnly: _favoritesOnly,
          sort: _sort,
        ),
      ),
    );
    final folders = ref.watch(foldersProvider);
    final stats = ref.watch(homeStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ScanFlow'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SearchAndActions(
                    query: _query,
                    grid: _grid,
                    favoritesOnly: _favoritesOnly,
                    sort: _sort,
                    onQueryChanged: (value) => setState(() => _query = value),
                    onGridChanged: (value) => setState(() => _grid = value),
                    onFavoritesChanged: () =>
                        setState(() => _favoritesOnly = !_favoritesOnly),
                    onSortChanged: (value) => setState(() => _sort = value),
                    onImport: _importImages,
                  ),
                  const SizedBox(height: 12),
                  stats.when(
                    data: (value) => _StatsRow(stats: value),
                    error: (error, _) => Text('Storage stats unavailable: $error'),
                    loading: () => const LinearProgressIndicator(),
                  ),
                  const SizedBox(height: 12),
                  folders.when(
                    data: (items) => _FolderRail(
                      folders: items,
                      selectedId: _folderId,
                      onSelected: (id) => setState(() => _folderId = id),
                      onCreate: _createFolder,
                    ),
                    error: (error, _) => Text('Folders unavailable: $error'),
                    loading: () => const SizedBox(height: 40),
                  ),
                ],
              ),
            ),
            Expanded(
              child: documents.when(
                data: (items) {
                  if (items.isEmpty) {
                    return EmptyState(
                      icon: Icons.document_scanner_outlined,
                      title: 'No scans yet',
                      message: _query.isEmpty
                          ? 'Capture a document or import images to build your first offline scan.'
                          : 'No document matches your search.',
                      action: FilledButton.icon(
                        onPressed: () => context.push('/scanner'),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Start scanning'),
                      ),
                    );
                  }
                  return _grid
                      ? _DocumentGrid(items: items, onAction: _handleAction)
                      : _DocumentList(items: items, onAction: _handleAction);
                },
                error: (error, _) => Center(child: Text('Could not load documents: $error')),
                loading: () => const Center(child: CircularProgressIndicator()),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/scanner'),
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scan'),
      ),
    );
  }

  Future<void> _importImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null) {
      return;
    }
    final files = result.paths.whereType<String>().map(File.new).toList();
    if (files.isEmpty || !mounted) {
      return;
    }
    final id = await ref.read(documentRepositoryProvider).createDocumentFromFiles(files);
    if (mounted) {
      context.push('/documents/$id');
    }
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Folder name'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) {
      return;
    }
    final id = await ref.read(documentRepositoryProvider).createFolder(name);
    setState(() => _folderId = id);
  }

  Future<void> _handleAction(_DocumentAction action, ScanDocument document) async {
    final repo = ref.read(documentRepositoryProvider);
    switch (action) {
      case _DocumentAction.open:
        context.push('/documents/${document.id}');
      case _DocumentAction.favorite:
        await repo.toggleFavorite(document);
      case _DocumentAction.rename:
        await _rename(document);
      case _DocumentAction.duplicate:
        await repo.duplicateDocument(document.id);
      case _DocumentAction.delete:
        await repo.softDeleteDocument(document.id);
      case _DocumentAction.sharePdf:
        await repo.sharePdf(document.id);
    }
  }

  Future<void> _rename(ScanDocument document) async {
    final controller = TextEditingController(text: document.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename document'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Document title'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (title == null || title.trim().isEmpty) {
      return;
    }
    await ref.read(documentRepositoryProvider).renameDocument(document.id, title);
  }
}

class _SearchAndActions extends StatelessWidget {
  const _SearchAndActions({
    required this.query,
    required this.grid,
    required this.favoritesOnly,
    required this.sort,
    required this.onQueryChanged,
    required this.onGridChanged,
    required this.onFavoritesChanged,
    required this.onSortChanged,
    required this.onImport,
  });

  final String query;
  final bool grid;
  final bool favoritesOnly;
  final DocumentSort sort;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<bool> onGridChanged;
  final VoidCallback onFavoritesChanged;
  final ValueChanged<DocumentSort> onSortChanged;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search scans and OCR text',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: onQueryChanged,
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: favoritesOnly ? 'Show all' : 'Favorites',
          onPressed: onFavoritesChanged,
          icon: Icon(favoritesOnly ? Icons.star : Icons.star_border),
        ),
        IconButton.filledTonal(
          tooltip: grid ? 'List view' : 'Grid view',
          onPressed: () => onGridChanged(!grid),
          icon: Icon(grid ? Icons.view_list_outlined : Icons.grid_view),
        ),
        PopupMenuButton<DocumentSort>(
          tooltip: 'Sort',
          icon: const Icon(Icons.sort),
          onSelected: onSortChanged,
          itemBuilder: (context) => const [
            PopupMenuItem(value: DocumentSort.recentlyEdited, child: Text('Recently edited')),
            PopupMenuItem(value: DocumentSort.newest, child: Text('Newest')),
            PopupMenuItem(value: DocumentSort.title, child: Text('Title')),
            PopupMenuItem(value: DocumentSort.pageCount, child: Text('Page count')),
          ],
        ),
        IconButton.filled(
          tooltip: 'Import images',
          onPressed: onImport,
          icon: const Icon(Icons.file_upload_outlined),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});

  final HomeStats stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatChip(label: 'Scans', value: '${stats.documents}'),
        _StatChip(label: 'Pages', value: '${stats.pages}'),
        _StatChip(label: 'Favorites', value: '${stats.favorites}'),
        _StatChip(label: 'Storage', value: _formatBytes(stats.storageBytes)),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderRail extends StatelessWidget {
  const _FolderRail({
    required this.folders,
    required this.selectedId,
    required this.onSelected,
    required this.onCreate,
  });

  final List<Folder> folders;
  final String? selectedId;
  final ValueChanged<String?> onSelected;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: selectedId == null,
            onSelected: (_) => onSelected(null),
          ),
          const SizedBox(width: 8),
          for (final folder in folders) ...[
            ChoiceChip(
              label: Text(folder.name),
              selected: selectedId == folder.id,
              onSelected: (_) => onSelected(folder.id),
            ),
            const SizedBox(width: 8),
          ],
          ActionChip(
            avatar: const Icon(Icons.create_new_folder_outlined),
            label: const Text('New'),
            onPressed: onCreate,
          ),
        ],
      ),
    );
  }
}

class _DocumentGrid extends StatelessWidget {
  const _DocumentGrid({required this.items, required this.onAction});

  final List<ScanDocument> items;
  final Future<void> Function(_DocumentAction, ScanDocument) onAction;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisExtent: 172,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _DocumentCard(
        document: items[index],
        onAction: onAction,
      ),
    );
  }
}

class _DocumentList extends StatelessWidget {
  const _DocumentList({required this.items, required this.onAction});

  final List<ScanDocument> items;
  final Future<void> Function(_DocumentAction, ScanDocument) onAction;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      itemBuilder: (context, index) => _DocumentCard(
        document: items[index],
        compact: true,
        onAction: onAction,
      ),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemCount: items.length,
    );
  }
}

enum _DocumentAction { open, favorite, rename, duplicate, delete, sharePdf }

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.document,
    required this.onAction,
    this.compact = false,
  });

  final ScanDocument document;
  final bool compact;
  final Future<void> Function(_DocumentAction, ScanDocument) onAction;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('MMM d, h:mm a');
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onAction(_DocumentAction.open, document),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: compact ? 52 : 64,
                height: compact ? 52 : 88,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.description_outlined, size: 32),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      document.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('${document.pageCount} pages'),
                    const SizedBox(height: 4),
                    Text('Edited ${formatter.format(document.updatedAt)}'),
                  ],
                ),
              ),
              PopupMenuButton<_DocumentAction>(
                onSelected: (action) => onAction(action, document),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _DocumentAction.favorite,
                    child: Text(document.isFavorite ? 'Remove favorite' : 'Favorite'),
                  ),
                  const PopupMenuItem(value: _DocumentAction.rename, child: Text('Rename')),
                  const PopupMenuItem(value: _DocumentAction.duplicate, child: Text('Duplicate')),
                  const PopupMenuItem(value: _DocumentAction.sharePdf, child: Text('Share PDF')),
                  const PopupMenuItem(value: _DocumentAction.delete, child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
