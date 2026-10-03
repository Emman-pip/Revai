import 'package:flutter/material.dart';

import '../models/quiz.dart';
import '../services/quiz_storage.dart';
import '../theme/app_theme.dart';

class QuizLibraryBrowser extends StatefulWidget {
  const QuizLibraryBrowser({
    super.key,
    required this.quizzes,
    required this.folders,
    required this.storage,
    required this.onOpen,
    required this.onReview,
    required this.onExport,
  });
  final List<SavedQuiz> quizzes;
  final List<QuizFolder> folders;
  final QuizStorage storage;
  final Future<void> Function(SavedQuiz) onOpen;
  final Future<void> Function(SavedQuiz) onReview;
  final Future<void> Function(SavedQuiz) onExport;

  @override
  State<QuizLibraryBrowser> createState() => _QuizLibraryBrowserState();
}

class _QuizLibraryBrowserState extends State<QuizLibraryBrowser> {
  String? folderId;
  final selected = <String>{};

  @override
  void didUpdateWidget(QuizLibraryBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.folders.any((folder) => folder.id == folderId)) folderId = null;
    selected.removeWhere(
      (id) => !widget.quizzes.any(
        (quiz) => quiz.id == id && quiz.folderId == folderId,
      ),
    );
  }

  Future<void> _perform(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
      }
    }
  }

  Future<void> _nameFolder([QuizFolder? folder]) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _FolderNameDialog(initialName: folder?.name),
    );
    if (name == null) return;
    await _perform(
      () => folder == null
          ? widget.storage.createFolder(name)
          : widget.storage.renameFolder(folder.id, name),
    );
  }

  Future<void> _deleteFolder(QuizFolder folder) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${folder.name}”?'),
        content: const Text('Its quizzes will be moved to Ungrouped.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete folder'),
          ),
        ],
      ),
    );
    if (remove == true) {
      await _perform(() => widget.storage.deleteFolder(folder.id));
    }
  }

  Future<void> _move(Set<String> ids) async {
    final destination = await showModalBottomSheet<({String? id})>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Move ${ids.length} quiz${ids.length == 1 ? '' : 'zes'}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Ungrouped'),
              onTap: () => Navigator.pop(context, (id: null)),
            ),
            for (final folder in widget.folders)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(folder.name),
                onTap: () => Navigator.pop(context, (id: folder.id)),
              ),
          ],
        ),
      ),
    );
    if (destination == null) return;
    await _perform(() async {
      await widget.storage.move(ids, destination.id);
      if (mounted) setState(selected.clear);
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.folders
        .where((folder) => folder.id == folderId)
        .firstOrNull;
    final quizzes = widget.quizzes
        .where((quiz) => quiz.folderId == folderId)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (current != null)
              IconButton(
                tooltip: 'Back to folders',
                onPressed: () => setState(() {
                  folderId = null;
                  selected.clear();
                }),
                icon: const Icon(Icons.arrow_back),
              ),
            Expanded(
              child: Text(
                current?.name ?? 'Folders',
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (selected.isNotEmpty) ...[
              Text('${selected.length} selected'),
              IconButton(
                tooltip: 'Move selected quizzes',
                onPressed: () => _move(Set.of(selected)),
                icon: const Icon(Icons.drive_file_move_outlined),
              ),
              IconButton(
                tooltip: 'Clear selection',
                onPressed: () => setState(selected.clear),
                icon: const Icon(Icons.close),
              ),
            ] else
              IconButton(
                tooltip: 'Create folder',
                onPressed: _nameFolder,
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
          ],
        ),
        if (current == null) ...[
          for (final folder in widget.folders)
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.folder_rounded,
                  color: context.colors.primary,
                ),
                title: Text(folder.name),
                subtitle: Text(
                  '${widget.quizzes.where((quiz) => quiz.folderId == folder.id).length} quizzes',
                ),
                onTap: () => setState(() {
                  folderId = folder.id;
                  selected.clear();
                }),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) => value == 'rename'
                      ? _nameFolder(folder)
                      : _deleteFolder(folder),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete folder'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text('Ungrouped', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
        ],
        if (quizzes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              current == null
                  ? 'Import PDF, DOCX, PPTX, Org, Markdown, or TXT to create a quiz. Long-press saved quizzes to group them.'
                  : 'This folder is empty. Move quizzes here from Ungrouped or another folder.',
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
          ),
        for (final quiz in quizzes)
          Card(
            color: selected.contains(quiz.id)
                ? context.colors.primaryContainer
                : context.colors.surfaceContainerLow,
            child: ListTile(
              onLongPress: () => setState(
                () => selected.contains(quiz.id)
                    ? selected.remove(quiz.id)
                    : selected.add(quiz.id),
              ),
              onTap: () {
                if (selected.isNotEmpty) {
                  setState(
                    () => selected.contains(quiz.id)
                        ? selected.remove(quiz.id)
                        : selected.add(quiz.id),
                  );
                } else {
                  _perform(() => widget.onOpen(quiz));
                }
              },
              leading: selected.isNotEmpty
                  ? Checkbox(
                      value: selected.contains(quiz.id),
                      onChanged: (value) => setState(
                        () => value!
                            ? selected.add(quiz.id)
                            : selected.remove(quiz.id),
                      ),
                    )
                  : Icon(Icons.quiz_outlined, color: context.colors.primary),
              title: Text(
                quiz.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${quiz.documentName} · ${quiz.questions.length} questions',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) => _perform(() async {
                  switch (value) {
                    case 'review':
                      await widget.onReview(quiz);
                    case 'move':
                      await _move({quiz.id});
                    case 'export':
                      await widget.onExport(quiz);
                    case 'delete':
                      await widget.storage.delete(quiz.id);
                  }
                }),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'review', child: Text('Review / edit')),
                  PopupMenuItem(value: 'move', child: Text('Move to folder')),
                  PopupMenuItem(value: 'export', child: Text('Share PDF')),
                  PopupMenuItem(value: 'delete', child: Text('Delete quiz')),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog({this.initialName});
  final String? initialName;
  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final controller = TextEditingController(text: widget.initialName);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initialName == null ? 'New folder' : 'Rename folder'),
    content: TextField(
      controller: controller,
      autofocus: true,
      maxLength: 60,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(labelText: 'Folder name'),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: const Text('Save'),
      ),
    ],
  );
}
