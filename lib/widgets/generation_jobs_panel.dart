import 'package:flutter/material.dart';

import '../models/quiz.dart';
import '../services/quiz_generation_queue.dart';
import '../theme/app_theme.dart';

class GenerationJobsPanel extends StatelessWidget {
  const GenerationJobsPanel({
    super.key,
    required this.queue,
    required this.onReview,
  });
  final QuizGenerationQueue queue;
  final Future<void> Function(SavedQuiz) onReview;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: queue,
    builder: (context, _) {
      if (queue.jobs.isEmpty) return const SizedBox.shrink();
      final waiting = queue.jobs
          .where((job) => job.status == GenerationStatus.queued)
          .length;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quiz generation',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                '$waiting waiting · one quiz uses the model at a time',
                style: TextStyle(
                  color: context.colors.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              if (queue.notificationNotice != null)
                Text(
                  queue.notificationNotice!,
                  style: TextStyle(
                    color: context.colors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final job in queue.jobs.reversed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    job.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (job.canCancel)
                                  TextButton(
                                    onPressed: () => queue.cancel(job),
                                    child: const Text('Cancel'),
                                  ),
                                if (job.status == GenerationStatus.completed)
                                  TextButton(
                                    onPressed: () => onReview(job.quiz!),
                                    child: const Text('Review'),
                                  ),
                                if (job.status == GenerationStatus.failed)
                                  PopupMenuButton<String>(
                                    tooltip: 'Recover ${job.title}',
                                    onSelected: (value) async {
                                      if (value == 'manual') {
                                        await queue.createManualDraft(job);
                                      } else {
                                        try {
                                          await queue.enqueue(
                                            job.document,
                                            job.settings,
                                            folderId: job.folderId,
                                          );
                                          queue.dismiss(job);
                                        } catch (error) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  error.toString().replaceFirst(
                                                    'Bad state: ',
                                                    '',
                                                  ),
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'retry',
                                        child: Text('Retry generation'),
                                      ),
                                      PopupMenuItem(
                                        value: 'manual',
                                        child: Text('Create manual draft'),
                                      ),
                                    ],
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      child: Text('Fix'),
                                    ),
                                  ),
                                if (job.finished)
                                  IconButton(
                                    tooltip: 'Dismiss ${job.title}',
                                    onPressed: () => queue.dismiss(job),
                                    icon: const Icon(Icons.close, size: 18),
                                  ),
                              ],
                            ),
                            Text(
                              job.stage,
                              style: TextStyle(
                                color: context.colors.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            if (job.error != null)
                              Text(
                                job.error!,
                                style: TextStyle(
                                  color: context.colors.error,
                                  fontSize: 12,
                                ),
                              ),
                            if (job.generatedOutput.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Container(
                                constraints: const BoxConstraints(
                                  maxHeight: 100,
                                ),
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: context.colors.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: SingleChildScrollView(
                                  child: SelectableText(
                                    job.generatedOutput,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ),
                            ],
                            if (!job.finished &&
                                job.status != GenerationStatus.queued) ...[
                              const SizedBox(height: 6),
                              const LinearProgressIndicator(),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
