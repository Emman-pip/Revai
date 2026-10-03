import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revai/main.dart';
import 'package:revai/models/quiz.dart';
import 'package:revai/services/local_model_service.dart';
import 'package:revai/services/quiz_generation_queue.dart';
import 'package:revai/services/quiz_generator.dart';
import 'package:revai/services/quiz_storage.dart';
import 'package:revai/theme/app_theme.dart';

void main() {
  testWidgets(
    'Question count changes rebalance difficulty with remainder to medium',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final model = LocalModelService();
      final storage = QuizStorage();
      final queue = QuizGenerationQueue(
        generator: QuizGenerator(model),
        storage: storage,
      );
      addTearDown(() {
        queue.dispose();
        storage.dispose();
        model.dispose();
      });
      await tester.pumpWidget(
        ThemeScope(
          setDarkMode: (_) {},
          child: MaterialApp(
            theme: buildAppTheme(Brightness.light),
            home: SetupPage(
              document: const SourceDocument(
                name: 'notes.txt',
                extension: 'txt',
                sections: [
                  SourceSection(id: 's1', label: 'Section 1', text: 'Notes.'),
                ],
              ),
              model: model,
              queue: queue,
              folders: const [],
            ),
          ),
        ),
      );

      String count(String label) => tester
          .widget<TextField>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is TextField && widget.decoration?.labelText == label,
            ),
          )
          .controller!
          .text;

      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Multiple choice',
        ),
        '6',
      );
      await tester.pump();

      expect(count('Easy'), '3');
      expect(count('Medium'), '5');
      expect(count('Hard'), '3');
    },
  );
}
