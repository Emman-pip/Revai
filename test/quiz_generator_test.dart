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

  @override
  Future<String> generate(
    String prompt, {
    GenerationCancellation? cancellation,
    void Function(String)? onToken,
  }) async {
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
    'returns empty editable draft when repaired output is still malformed',
    () async {
      final model = _FakeModel(['not json', 'still not json']);

      final quiz = await QuizGenerator(model).generate(_document, _settings());

      expect(model.calls, 2);
      expect(quiz.questions, isEmpty);
    },
  );
}
