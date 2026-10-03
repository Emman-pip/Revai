import 'package:flutter_test/flutter_test.dart';
import 'package:revai/models/quiz.dart';
import 'package:revai/services/generation_cancellation.dart';
import 'package:revai/services/local_model_service.dart';
import 'package:revai/services/quiz_generator.dart';

const _document = SourceDocument(
  name: 'notes.txt',
  extension: 'txt',
  sections: [
    SourceSection(id: 's1', label: 'Section 1', text: 'Cells have membranes.'),
  ],
);

QuizSettings _settings() => const QuizSettings(
  title: 'Biology',
  mode: ExamMode.multipleChoice,
  multipleChoiceCount: 1,
  identificationCount: 0,
  easyCount: 1,
  mediumCount: 0,
  hardCount: 0,
);

class _FakeModel extends LocalModelService {
  _FakeModel(this.responses);
  final List<String> responses;
  int calls = 0;
  final prompts = <String>[];

  @override
  Future<String> generate(
    String prompt, {
    GenerationCancellation? cancellation,
    void Function(String)? onToken,
  }) async {
    prompts.add(prompt);
    final response = responses[calls++];
    onToken?.call(response);
    return response;
  }
}

void main() {
  test(
    'salvages questions with mismatched source and incomplete options',
    () async {
      final model = _FakeModel([
        '''{"questions":[{"kind":"multiple_choice","prompt":"What do cells have?","answer":"Membranes","source_id":"wrong-id","source_excerpt":"not copied exactly","options":["Membranes"]}]}''',
      ]);

      final quiz = await QuizGenerator(model).generate(_document, _settings());

      expect(model.calls, 1);
      expect(quiz.questions, hasLength(1));
      expect(quiz.questions.single.sourceId, 's1');
      expect(quiz.questions.single.options, contains('Membranes'));
    },
  );

  test(
    'keeps an editable empty draft after three failed repair attempts',
    () async {
      final model = _FakeModel([
        'not json',
        'still not json',
        'nope',
        'also nope',
      ]);

      final quiz = await QuizGenerator(model).generate(_document, _settings());

      expect(model.calls, 4);
      expect(quiz.questions, isEmpty);
      expect(model.prompts[1], contains('Invalid JSON syntax'));
    },
  );

  test('repairs invalid JSON and retains a valid partial question set', () async {
    const partial =
        '{"questions":[{"kind":"multiple_choice","prompt":"What do cells have?","answer":"Membranes","source_id":"s1","source_excerpt":"Cells have membranes.","options":["Membranes","Nucleus","DNA","ATP"]}]}';
    final model = _FakeModel(['{"questions": [', partial]);

    final quiz = await QuizGenerator(model).generate(_document, _settings());

    expect(model.calls, 2);
    expect(model.prompts[1], contains('Unexpected end'));
    expect(quiz.questions, hasLength(1));
  });

  test('does not ask for more questions when valid output is short', () async {
    const partial =
        '{"questions":[{"kind":"identification","prompt":"What do cells have?","answer":"Membranes","source_id":"s1","source_excerpt":"Cells have membranes."}]}';
    final model = _FakeModel([partial]);

    final quiz = await QuizGenerator(model).generate(_document, _settings());

    expect(model.calls, 1);
    expect(quiz.questions, hasLength(1));
  });
}
