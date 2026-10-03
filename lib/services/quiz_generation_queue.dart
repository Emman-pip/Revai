import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/quiz.dart';
import 'generation_cancellation.dart';
import 'generation_notifications.dart';
import 'quiz_generator.dart';
import 'quiz_storage.dart';

enum GenerationStatus {
  queued,
  running,
  stopping,
  saving,
  completed,
  failed,
  cancelled,
}

class GenerationJob {
  GenerationJob({
    required this.document,
    required this.settings,
    this.folderId,
    this.onReleaseModel,
  });
  final SourceDocument document;
  final QuizSettings settings;
  final String? folderId;
  final VoidCallback? onReleaseModel;
  bool _reservationReleased = false;

  void _releaseReservation() {
    if (_reservationReleased) return;
    _reservationReleased = true;
    onReleaseModel?.call();
  }

  final cancellation = GenerationCancellation();
  GenerationStatus status = GenerationStatus.queued;
  String stage = 'Waiting for the model';
  String? error;
  String generatedOutput = '';
  SavedQuiz? quiz;
  bool get canCancel =>
      status == GenerationStatus.queued || status == GenerationStatus.running;
  bool get finished =>
      status == GenerationStatus.completed ||
      status == GenerationStatus.failed ||
      status == GenerationStatus.cancelled;
  String get title =>
      settings.title.trim().isEmpty ? 'Untitled quiz' : settings.title.trim();
}

class QuizGenerationQueue extends ChangeNotifier {
  QuizGenerationQueue({
    required this.generator,
    required this.storage,
    GenerationNotifications? notifications,
  }) : notifications = notifications ?? GenerationNotifications();
  final QuizGenerator generator;
  final QuizStorage storage;
  final GenerationNotifications notifications;
  final List<GenerationJob> _jobs = [];
  List<GenerationJob> get jobs => List.unmodifiable(_jobs);
  bool _pumping = false;
  Future<void> _operations = Future.value();
  String? notificationNotice;

  // Serialize service start/stop with enqueue, including the last-job boundary.
  Future<void> _serviceOperation(Future<void> Function() operation) {
    final next = _operations.then((_) => operation());
    _operations = next.catchError((Object _) {});
    return next;
  }

  Future<void> enqueue(
    SourceDocument document,
    QuizSettings settings, {
    String? folderId,
  }) {
    generator.validateRequest(document, settings);
    // Reserve before notification permission or other async work. A queued
    // request must continue to use the model selected when it was submitted.
    final release = generator.model.reserveSelection();
    return _serviceOperation(() async {
      if (!_jobs.any((job) => !job.finished)) {
        try {
          final allowed = await notifications.requestPermission();
          notificationNotice = allowed
              ? null
              : 'Notifications are off. Follow progress here.';
          await notifications.start();
        } catch (_) {
          notificationNotice =
              'Background notifications are unavailable. Keep Revai open while generating.';
        }
      }
      _jobs.add(
        GenerationJob(
          document: document,
          settings: settings,
          folderId: folderId,
          onReleaseModel: release,
        ),
      );
      final active = _jobs
          .where((job) => job.status == GenerationStatus.running)
          .firstOrNull;
      if (active != null) unawaited(_updateNotification(active));
      notifyListeners();
      unawaited(_pump());
    }).catchError((Object error, StackTrace stack) {
      release();
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> _updateNotification(GenerationJob job) async {
    try {
      await notifications.update(
        job.title,
        job.stage,
        _jobs.where((item) => item.status == GenerationStatus.queued).length,
      );
    } catch (_) {
      notificationNotice =
          'Progress notifications are unavailable. Follow progress here.';
    }
  }

  Future<void> cancel(GenerationJob job) async {
    if (!job.canCancel) return;
    final wasQueued = job.status == GenerationStatus.queued;
    job.status = wasQueued
        ? GenerationStatus.cancelled
        : GenerationStatus.stopping;
    job.stage = wasQueued ? 'Cancelled' : 'Stopping the model…';
    if (wasQueued) job._releaseReservation();
    notifyListeners();
    final active = wasQueued
        ? _jobs
              .where((item) => item.status == GenerationStatus.running)
              .firstOrNull
        : job;
    if (active != null) unawaited(_updateNotification(active));
    try {
      await job.cancellation.cancel();
    } catch (_) {
      // Keep ownership of the model until its stream and cleanup finish.
      job.stage = 'Stopping… waiting for the model to release';
      notifyListeners();
    }
  }

  void dismiss(GenerationJob job) {
    if (!job.finished) return;
    _jobs.remove(job);
    notifyListeners();
  }

  Future<void> createManualDraft(GenerationJob job) async {
    if (job.status != GenerationStatus.failed) return;
    final draft = SavedQuiz(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: job.title,
      documentName: job.document.name,
      createdAt: DateTime.now(),
      mode: job.settings.mode,
      questions: const [],
    ).withFolder(job.folderId);
    await storage.save(draft);
    job.quiz = draft;
    job.status = GenerationStatus.completed;
    job.error = null;
    job.stage = 'Manual draft ready to review';
    notifyListeners();
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (true) {
        final job = _jobs
            .where((item) => item.status == GenerationStatus.queued)
            .firstOrNull;
        if (job == null) break;
        job.status = GenerationStatus.running;
        job.stage = 'Loading the model';
        notifyListeners();
        await _updateNotification(job);
        try {
          final quiz = await generator.generate(
            job.document,
            job.settings,
            cancellation: job.cancellation,
            onStage: (stage) {
              if (job.cancellation.isCancelled) return;
              job.stage = stage;
              notifyListeners();
              unawaited(_updateNotification(job));
            },
            onOutput: (chunk) {
              if (job.cancellation.isCancelled) return;
              job.generatedOutput = (job.generatedOutput + chunk);
              if (job.generatedOutput.length > 4000) {
                job.generatedOutput = job.generatedOutput.substring(
                  job.generatedOutput.length - 4000,
                );
              }
              notifyListeners();
            },
          );
          job.cancellation.check();
          job.status = GenerationStatus.saving;
          job.stage = 'Saving quiz';
          notifyListeners();
          await _updateNotification(job);
          await storage.save(quiz.withFolder(job.folderId));
          job.quiz = quiz.withFolder(job.folderId);
          job.status = GenerationStatus.completed;
          job.stage = quiz.questions.isEmpty
              ? 'No usable questions · add them manually'
              : 'Ready to review · ${quiz.questions.length} questions';
        } catch (error) {
          if (job.cancellation.isCancelled || error is GenerationCancelled) {
            job.status = GenerationStatus.cancelled;
            job.stage = 'Cancelled';
          } else {
            job.status = GenerationStatus.failed;
            job.stage = 'Could not generate quiz';
            job.error = error.toString().replaceFirst('Bad state: ', '');
          }
        } finally {
          job._releaseReservation();
        }
        notifyListeners();
        if (job.status != GenerationStatus.cancelled) {
          try {
            await notifications.completed(
              job.title,
              job.status == GenerationStatus.completed,
            );
          } catch (_) {
            /* Notification failure must not discard a saved quiz. */
          }
        }
      }
    } finally {
      _pumping = false;
      await _serviceOperation(() async {
        if (!_jobs.any((job) => !job.finished)) {
          try {
            await notifications.stop();
          } catch (_) {}
        }
      });
    }
  }
}
