import 'dart:convert';
import 'dart:math';

import '../models/quiz.dart';
import 'local_model_service.dart';
import 'generation_cancellation.dart';

class QuizSettings {
  const QuizSettings({
    required this.title,
    required this.mode,
    required this.multipleChoiceCount,
    required this.identificationCount,
    required this.easyCount,
    required this.mediumCount,
    required this.hardCount,
    this.coverageIds = const {},
  });

  final String title;
  final ExamMode mode;
  final int multipleChoiceCount;
  final int identificationCount;
  final int easyCount;
  final int mediumCount;
  final int hardCount;
  final Set<String> coverageIds;

  int get totalCount => multipleChoiceCount + identificationCount;
}

class QuizGenerator {
  static const _maxRepairAttempts = 3;

  QuizGenerator(this.model);
  final LocalModelService model;

  void validateRequest(SourceDocument document, QuizSettings settings) {
    _prepareSource(document, settings);
  }

  ({List<SourceSection> sections, String source}) _prepareSource(
    SourceDocument document,
    QuizSettings settings,
  ) {
    final selected = model.selectedModel;
    if (selected == null) {
      throw StateError('Download and select an AI model on the home screen.');
    }
    if (settings.totalCount < 1 ||
        settings.totalCount > selected.maxQuizQuestions) {
      throw StateError(
        '${selected.name} supports 1–${selected.maxQuizQuestions} questions per quiz. '
        'Reduce the question count or select another model.',
      );
    }
    final sections = document.sections
        .where(
          (section) =>
              settings.coverageIds.isEmpty ||
              settings.coverageIds.contains(section.id),
        )
        .toList();
    if (sections.isEmpty) {
      throw StateError('Choose at least one document section.');
    }
    final source = sections
        .map((section) => '[${section.id} | ${section.label}]\n${section.text}')
        .join('\n\n');
    if (source.length > selected.maxSourceCharacters) {
      throw StateError(
        '${selected.name} supports up to ${selected.maxSourceCharacters} source characters per quiz. '
        'Narrow the page or section coverage, or select another model.',
      );
    }
    return (sections: sections, source: source);
  }

  Future<SavedQuiz> generate(
    SourceDocument document,
    QuizSettings settings, {
    GenerationCancellation? cancellation,
    void Function(String)? onStage,
    void Function(String)? onOutput,
  }) async {
    cancellation?.check();
    final release = model.reserveSelection();
    try {
      onStage?.call('Preparing source');
      final prepared = _prepareSource(document, settings);
      final sections = prepared.sections;
      final source = prepared.source;
      final prompt = _prompt(source, settings);
      onStage?.call('Writing questions');
      var raw = await model.generate(
        prompt,
        cancellation: cancellation,
        onToken: onOutput,
      );
      cancellation?.check();
      onStage?.call('Checking answers and sources');
      var feedback = _jsonValidationError(raw);
      var generated = _salvageQuestions(raw, sections);
      for (
        var attempt = 1;
        feedback != null && attempt <= _maxRepairAttempts;
        attempt++
      ) {
        cancellation?.check();
        onStage?.call(
          'Repairing response format ($attempt/$_maxRepairAttempts)',
        );
        raw = await model.generate(
          '''Fix the JSON validation error below. Return exactly one JSON object with a top-level "questions" array. Preserve all recoverable questions and their content. Do not add prose or Markdown.

Validation feedback:
$feedback

Previous response:
$raw''',
          cancellation: cancellation,
          onToken: onOutput,
        );
        cancellation?.check();
        onStage?.call('Checking answers and sources');
        feedback = _jsonValidationError(raw);
        final repairedQuestions = _salvageQuestions(raw, sections);
        if (repairedQuestions.length >= generated.length) {
          generated = repairedQuestions;
        }
      }

      // Keep the most complete recoverable set if the repair budget is spent.
      final balanced = _balanceOptions(generated);
      return SavedQuiz(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: settings.title.trim().isEmpty
            ? 'Untitled quiz'
            : settings.title.trim(),
        documentName: document.name,
        createdAt: DateTime.now(),
        mode: settings.mode,
        questions: balanced,
      );
    } finally {
      release();
    }
  }

  String? _jsonValidationError(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      return 'Invalid JSON syntax: ${error.message}';
    }
    if (decoded is! Map<String, dynamic>) {
      return 'The JSON root must be an object.';
    }
    if (decoded['questions'] is! List) {
      return 'The JSON object must contain a "questions" array.';
    }
    return null;
  }

  List<QuizQuestion> _salvageQuestions(
    String raw,
    List<SourceSection> sections,
  ) {
    try {
      return _parse(raw, sections);
    } on _QuizResponseFormatException {
      return const [];
    }
  }

  String _prompt(String source, QuizSettings settings) {
    final kinds = [
      if (settings.multipleChoiceCount > 0)
        '${settings.multipleChoiceCount} multiple_choice',
      if (settings.identificationCount > 0)
        '${settings.identificationCount} identification',
    ].join(' and ');
    return '''Create exactly ${settings.totalCount} study-exam questions using only the document text below.
Return one JSON object only: {"questions":[...]}. No Markdown fences or extra prose.

Produce $kinds questions, with exactly ${settings.easyCount} easy, ${settings.mediumCount} medium, and ${settings.hardCount} hard questions overall. Preserve the source language. Most prompts and all answers must follow the document's wording closely. Do not introduce facts from outside the document. Use direct, concise prompts. Every source_excerpt must be copied word-for-word from its cited section and be enough to verify the answer.

Each question object must contain: kind ("multiple_choice" or "identification"), prompt, answer, source_id, source_excerpt, explanation, difficulty ("easy", "medium", or "hard"), options (exactly four distinct strings for multiple choice; empty array for identification). For multiple choice, answer must exactly equal one options entry. Use plausible but source-grounded distractors.

Document sections:
$source''';
  }

  List<QuizQuestion> _parse(String raw, List<SourceSection> sections) {
    final value = _decodeResponse(raw);
    if (value is! Map<String, dynamic> || value['questions'] is! List) {
      throw const _QuizResponseFormatException();
    }
    final records = (value['questions'] as List).cast<Object?>();
    final sourceById = {for (final section in sections) section.id: section};
    final questions = <QuizQuestion>[];
    for (final item in records) {
      if (item is! Map) continue;
      final record = item.cast<String, Object?>();
      final kindName = _string(record['kind'])?.toLowerCase();
      final kind = switch (kindName) {
        'multiple_choice' ||
        'multiple choice' ||
        'mcq' => QuestionKind.multipleChoice,
        'identification' => QuestionKind.identification,
        _ => QuestionKind.identification,
      };
      final prompt =
          _string(record['prompt'] ?? record['question'])?.trim() ?? '';
      final answer =
          _string(record['answer'] ?? record['correct_answer'])?.trim() ?? '';
      if (prompt.isEmpty || answer.isEmpty) continue;
      final suppliedSourceId =
          _string(record['source_id'] ?? record['sourceId']) ?? '';
      final suppliedExcerpt =
          _string(
            record['source_excerpt'] ?? record['sourceExcerpt'],
          )?.trim() ??
          '';
      final section =
          sourceById[suppliedSourceId] ??
          sections.firstWhere(
            (candidate) =>
                suppliedExcerpt.isNotEmpty &&
                _normalize(
                  candidate.text,
                ).contains(_normalize(suppliedExcerpt)),
            orElse: () => sections.first,
          );
      final excerpt = suppliedExcerpt.isNotEmpty
          ? suppliedExcerpt
          : section.text;
      final difficultyValue = (_string(record['difficulty']) ?? 'medium')
          .toLowerCase();
      final difficulty =
          const {'easy', 'medium', 'hard'}.contains(difficultyValue)
          ? difficultyValue
          : 'medium';
      final optionValue = record['options'];
      final options = (optionValue is List ? optionValue : const [])
          .whereType<String>()
          .map((option) => option.trim())
          .where((option) => option.isNotEmpty)
          .toSet()
          .toList();
      questions.add(
        QuizQuestion(
          id: '${DateTime.now().microsecondsSinceEpoch}-${questions.length}',
          kind: kind,
          prompt: prompt,
          answer: answer,
          sourceId: section.id,
          sourceLabel: section.label,
          sourceExcerpt: excerpt,
          options: options,
          explanation: _string(record['explanation'])?.trim() ?? '',
          difficulty: difficulty,
        ),
      );
    }
    return questions;
  }

  Object? _decodeResponse(String raw) {
    for (
      var start = raw.indexOf('{');
      start >= 0;
      start = raw.indexOf('{', start + 1)
    ) {
      var depth = 0;
      var inString = false;
      var escaped = false;
      for (var i = start; i < raw.length; i++) {
        final char = raw[i];
        if (inString) {
          if (escaped) {
            escaped = false;
          } else if (char == r'\') {
            escaped = true;
          } else if (char == '"') {
            inString = false;
          }
          continue;
        }
        if (char == '"') {
          inString = true;
        } else if (char == '{') {
          depth++;
        } else if (char == '}' && --depth == 0) {
          try {
            return jsonDecode(raw.substring(start, i + 1));
          } on FormatException {
            break;
          }
        }
      }
    }
    throw const _QuizResponseFormatException();
  }

  String? _string(Object? value) => value is String ? value : null;

  List<QuizQuestion> _balanceOptions(List<QuizQuestion> input) {
    final random = Random.secure();
    final mcIndexes = [
      for (var i = 0; i < input.length; i++)
        if (input[i].kind == QuestionKind.multipleChoice) i,
    ];
    final positions = <int>[];
    for (var i = 0; i < mcIndexes.length; i++) {
      positions.add(i % 4);
    }
    do {
      positions.shuffle(random);
    } while (_hasPositionPattern(positions));

    var nextMc = 0;
    return [
      for (final question in input)
        if (question.kind == QuestionKind.multipleChoice)
          _placeCorrectAnswer(question, positions[nextMc++])
        else
          question,
    ];
  }

  QuizQuestion _placeCorrectAnswer(QuizQuestion question, int correctIndex) {
    final hasFourDistinctOptions =
        question.options.length == 4 && question.options.toSet().length == 4;
    final hasCorrectOption = question.options.any(
      (option) => _normalize(option) == _normalize(question.answer),
    );
    if (!hasFourDistinctOptions || !hasCorrectOption) {
      final alternatives = question.options
          .where((option) => _normalize(option) != _normalize(question.answer))
          .take(3);
      return question.copyWith(options: [question.answer, ...alternatives]);
    }
    final random = Random.secure();
    final alternatives =
        question.options
            .where(
              (option) => _normalize(option) != _normalize(question.answer),
            )
            .toList()
          ..shuffle(random);
    final choices = [...alternatives]..insert(correctIndex, question.answer);
    return question.copyWith(options: choices);
  }

  bool _hasPositionPattern(List<int> positions) {
    for (var i = 2; i < positions.length; i++) {
      if (positions[i] == positions[i - 1] &&
          positions[i] == positions[i - 2]) {
        return true;
      }
    }
    for (final period in [2, 3]) {
      if (positions.length >= period * 2 &&
          positions
              .skip(period)
              .toList()
              .asMap()
              .entries
              .every((entry) => entry.value == positions[entry.key])) {
        return true;
      }
    }
    return false;
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
}

class _QuizResponseFormatException implements Exception {
  const _QuizResponseFormatException();
}
