import 'dart:convert';

enum ExamMode { multipleChoice, identification, hybrid }

enum QuestionKind { multipleChoice, identification }

class SourceSection {
  const SourceSection({
    required this.id,
    required this.label,
    required this.text,
  });

  final String id;
  final String label;
  final String text;
}

class SourceDocument {
  const SourceDocument({
    required this.name,
    required this.extension,
    required this.sections,
  });

  final String name;
  final String extension;
  final List<SourceSection> sections;

  String get text => sections.map((section) => section.text).join('\n\n');
}

class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.kind,
    required this.prompt,
    required this.answer,
    required this.sourceId,
    required this.sourceLabel,
    required this.sourceExcerpt,
    this.options = const [],
    this.explanation = '',
    this.difficulty = 'medium',
  });

  final String id;
  final QuestionKind kind;
  final String prompt;
  final String answer;
  final String sourceId;
  final String sourceLabel;
  final String sourceExcerpt;
  final List<String> options;
  final String explanation;
  final String difficulty;

  QuizQuestion copyWith({
    QuestionKind? kind,
    String? prompt,
    String? answer,
    String? sourceId,
    String? sourceLabel,
    String? sourceExcerpt,
    List<String>? options,
    String? explanation,
    String? difficulty,
  }) => QuizQuestion(
    id: id,
    kind: kind ?? this.kind,
    prompt: prompt ?? this.prompt,
    answer: answer ?? this.answer,
    sourceId: sourceId ?? this.sourceId,
    sourceLabel: sourceLabel ?? this.sourceLabel,
    sourceExcerpt: sourceExcerpt ?? this.sourceExcerpt,
    options: options ?? this.options,
    explanation: explanation ?? this.explanation,
    difficulty: difficulty ?? this.difficulty,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'prompt': prompt,
    'answer': answer,
    'sourceId': sourceId,
    'sourceLabel': sourceLabel,
    'sourceExcerpt': sourceExcerpt,
    'options': options,
    'explanation': explanation,
    'difficulty': difficulty,
  };

  factory QuizQuestion.fromJson(Map<String, Object?> json) => QuizQuestion(
    id: json['id'] as String,
    kind: QuestionKind.values.byName(json['kind'] as String),
    prompt: json['prompt'] as String,
    answer: json['answer'] as String,
    sourceId: json['sourceId'] as String,
    sourceLabel: json['sourceLabel'] as String? ?? json['sourceId'] as String,
    sourceExcerpt: json['sourceExcerpt'] as String? ?? '',
    options: (json['options'] as List<Object?>? ?? const []).cast<String>(),
    explanation: json['explanation'] as String? ?? '',
    difficulty: json['difficulty'] as String? ?? 'medium',
  );
}

class SavedQuiz {
  const SavedQuiz({
    required this.id,
    required this.title,
    required this.documentName,
    required this.createdAt,
    required this.mode,
    required this.questions,
    this.folderId,
  });

  final String id;
  final String title;
  final String documentName;
  final DateTime createdAt;
  final ExamMode mode;
  final List<QuizQuestion> questions;
  final String? folderId;

  SavedQuiz withFolder(String? folderId) => SavedQuiz(
    id: id,
    title: title,
    documentName: documentName,
    createdAt: createdAt,
    mode: mode,
    questions: questions,
    folderId: folderId,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'documentName': documentName,
    'createdAt': createdAt.toIso8601String(),
    'mode': mode.name,
    'questions': questions.map((q) => q.toJson()).toList(),
    'folderId': folderId,
  };

  factory SavedQuiz.fromJson(Map<String, Object?> json) => SavedQuiz(
    id: json['id'] as String,
    title: json['title'] as String,
    documentName: json['documentName'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    mode: ExamMode.values.byName(json['mode'] as String),
    folderId: json['folderId'] as String?,
    questions: (json['questions'] as List<Object?>)
        .map((q) => QuizQuestion.fromJson(q as Map<String, Object?>))
        .toList(),
  );
}

class QuizFolder {
  const QuizFolder({required this.id, required this.name});
  final String id;
  final String name;

  Map<String, Object?> toJson() => {'id': id, 'name': name};
  factory QuizFolder.fromJson(Map<String, Object?> json) =>
      QuizFolder(id: json['id'] as String, name: json['name'] as String);
}

String encodeQuizzes(List<SavedQuiz> quizzes) =>
    jsonEncode(quizzes.map((quiz) => quiz.toJson()).toList());

List<SavedQuiz> decodeQuizzes(String json) =>
    (jsonDecode(json) as List<Object?>)
        .map((item) => SavedQuiz.fromJson(item as Map<String, Object?>))
        .toList();
