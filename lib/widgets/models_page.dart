import 'package:flutter/material.dart';

import '../services/device_readiness.dart';
import '../services/local_model_service.dart';
import '../services/model_catalog.dart';
import '../theme/app_theme.dart';

class ModelsPage extends StatefulWidget {
  const ModelsPage({super.key, required this.model, this.deviceReadiness});

  final LocalModelService model;
  final DeviceReadiness? deviceReadiness;

  @override
  State<ModelsPage> createState() => _ModelsPageState();
}

class _ModelsPageState extends State<ModelsPage> {
  bool _working = false;
  String? _error;

  Future<void> _perform(Future<void> Function() operation) async {
    if (_working || !widget.model.canManage) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Bad state: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _download(LocalAiModel choice) => _perform(() async {
    final readiness = widget.deviceReadiness ?? DeviceReadiness();
    final issue = await readiness.checkForModelDownload(
      requiredFreeBytes: choice.requiredFreeBytes,
    );
    if (issue != null) throw StateError(issue);
    try {
      await widget.model.download(model: choice, onProgress: (_) {});
    } catch (error) {
      throw StateError(
        'Download did not finish. Check your connection and free storage, then retry. '
        '${error.toString().replaceFirst('Bad state: ', '')}',
      );
    }
  });

  Future<void> _remove(LocalAiModel choice) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${choice.name}?'),
        content: const Text(
          'This frees its downloaded model storage. You can download it again later. Your saved quizzes are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _perform(() => widget.model.removeModel(choice));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Offline AI models'),
      actions: const [ThemeToggle()],
    ),
    body: ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Choose one model for quizzes and AI chat.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Internet is needed to download a model. Once downloaded, it works offline. '
            'Additional downloads keep your current selection until you tap Use model. '
            'Android 12+ and at least 8 GB RAM are required.',
          ),
          if (widget.model.isInUse) ...[
            const SizedBox(height: 12),
            const Text(
              'Finish or cancel quiz jobs and leave AI chat to change, download, or remove models.',
            ),
          ],
          if (_working || widget.model.isManaging) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: context.colors.error)),
          ],
          const SizedBox(height: 16),
          for (final choice in localAiModels) _modelCard(choice),
        ],
      ),
    ),
  );

  Widget _modelCard(LocalAiModel choice) {
    final service = widget.model;
    final installed = service.isDownloaded(choice);
    final selected = installed && service.selectedModel?.id == choice.id;
    final downloading = service.downloadingId == choice.id;
    final enabled = service.canManage && !_working;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(choice.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${choice.sizeLabel} · ${selected
                  ? 'Selected'
                  : installed
                  ? 'Downloaded'
                  : 'Not downloaded'}',
            ),
            const SizedBox(height: 8),
            Text(choice.description),
            const SizedBox(height: 6),
            Text(
              choice.quizLimits,
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
            if (downloading) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: service.downloadProgress == 0
                    ? null
                    : service.downloadProgress / 100,
              ),
              Text('Downloading · ${service.downloadProgress}%'),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (installed)
                  FilledButton.icon(
                    key: ValueKey('select-${choice.id}'),
                    onPressed: enabled && !selected
                        ? () => _perform(() => service.selectModel(choice))
                        : null,
                    icon: Icon(selected ? Icons.check : Icons.memory_rounded),
                    label: Text(selected ? 'Selected' : 'Use model'),
                  )
                else
                  FilledButton.icon(
                    key: ValueKey('download-${choice.id}'),
                    onPressed: enabled ? () => _download(choice) : null,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Download'),
                  ),
                if (installed)
                  IconButton(
                    tooltip: 'Remove ${choice.name}',
                    onPressed: enabled ? () => _remove(choice) : null,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
