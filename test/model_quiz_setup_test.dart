import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revai/main.dart';
import 'package:revai/models/quiz.dart';
import 'package:revai/services/local_model_service.dart';
import 'package:revai/services/model_catalog.dart';
import 'package:revai/services/quiz_generation_queue.dart';
import 'package:revai/services/quiz_generator.dart';
import 'package:revai/services/quiz_storage.dart';
import 'package:revai/theme/app_theme.dart';

import 'support/fake_model_backend.dart';

void main() {
  testWidgets(
    'Compact model shows limits, keeps mode defaults within them, and rejects long coverage before enqueue',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final backend = FakeModelBackend()..installed.add(localAiModels.last.id);
      final service = LocalModelService(
        backend: backend,
        preferences: MemoryModelPreferences(),
      );
      await service.initialize();
      final storage = QuizStorage();
      final queue = QuizGenerationQueue(
        generator: QuizGenerator(service),
        storage: storage,
      );
      addTearDown(() {
        queue.dispose();
        storage.dispose();
        service.dispose();
      });
      final document = SourceDocument(
        name: 'long.txt',
        extension: 'txt',
        sections: [
          SourceSection(id: 's1', label: 'Section 1', text: 'x' * 6001),
        ],
      );
      await tester.pumpWidget(
        ThemeScope(
          setDarkMode: (_) {},
          child: MaterialApp(
            theme: buildAppTheme(Brightness.light),
            home: SetupPage(
              document: document,
              model: service,
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
      expect(
        find.textContaining('Up to 5 questions · 6000 source characters'),
        findsOneWidget,
      );
      expect(count('Multiple choice'), '3');
      expect(count('Identification'), '2');
      await tester.tap(find.widgetWithText(InkWell, 'Multiple choice'));
      await tester.pumpAndSettle();
      expect(count('Multiple choice'), '5');
      await tester.tap(find.widgetWithText(InkWell, 'Identification'));
      await tester.pumpAndSettle();
      expect(count('Identification'), '5');
      await tester.tap(find.text('Generate in background'));
      await tester.pumpAndSettle();
      expect(queue.jobs, isEmpty);
      expect(backend.loaded, isEmpty);
      await tester.scrollUntilVisible(
        find.textContaining('6000 source characters per quiz.'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('Narrow the page or section coverage'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
