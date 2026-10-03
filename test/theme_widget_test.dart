import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revai/main.dart';
import 'package:revai/models/quiz.dart';
import 'package:revai/services/local_model_service.dart';
import 'package:revai/services/quiz_generation_queue.dart';
import 'package:revai/services/quiz_generator.dart';
import 'package:revai/services/quiz_pdf_exporter.dart';
import 'package:revai/services/quiz_storage.dart';
import 'package:revai/theme/app_theme.dart';

class MemoryStorage extends QuizStorage {
  @override
  Future<QuizLibrary> loadLibrary() async =>
      (quizzes: <SavedQuiz>[], folders: <QuizFolder>[]);
}

class OfflineModel extends LocalModelService {
  @override
  Future<bool> isInstalled() async => false;
}

class ThemeHarness extends StatefulWidget {
  const ThemeHarness({super.key, required this.home});
  final Widget home;
  @override
  State<ThemeHarness> createState() => _ThemeHarnessState();
}

class _ThemeHarnessState extends State<ThemeHarness> {
  ThemeMode mode = ThemeMode.light;
  @override
  Widget build(BuildContext context) => ThemeScope(
    setDarkMode: (dark) =>
        setState(() => mode = dark ? ThemeMode.dark : ThemeMode.light),
    child: MaterialApp(
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: mode,
      home: widget.home,
    ),
  );
}

void main() {
  testWidgets('Home replaces the badge with an accessible light/dark toggle', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final model = OfflineModel();
    final storage = MemoryStorage();
    final queue = QuizGenerationQueue(
      generator: QuizGenerator(model),
      storage: storage,
    );
    addTearDown(() {
      queue.dispose();
      storage.dispose();
    });
    await tester.pumpWidget(
      ThemeHarness(
        home: HomePage(model: model, storage: storage, queue: queue),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('What would you like to do?'), findsOneWidget);
    expect(find.text('Chat with AI'), findsOneWidget);
    expect(find.text('Quiz Maker'), findsOneWidget);
    expect(find.text('New quiz'), findsNothing);
    expect(find.text('ON DEVICE'), findsNothing);
    expect(find.byTooltip('Switch to dark theme'), findsOneWidget);
    await tester.tap(find.byTooltip('Switch to dark theme'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(HomePage))).brightness,
      Brightness.dark,
    );
    expect(find.byTooltip('Switch to light theme'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Switch to light theme'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(HomePage))).brightness,
      Brightness.light,
    );
  });

  testWidgets('Study theme toggles without resetting the revealed answer', (
    tester,
  ) async {
    final quiz = SavedQuiz(
      id: 'one',
      title: 'Biology',
      documentName: 'notes.md',
      createdAt: DateTime(2026),
      mode: ExamMode.multipleChoice,
      questions: const [
        QuizQuestion(
          id: 'q1',
          kind: QuestionKind.multipleChoice,
          prompt: 'What protects the cell?',
          answer: 'Membrane',
          sourceId: 't1',
          sourceLabel: 'Cells · line 3',
          sourceExcerpt: 'The membrane protects the cell.',
          options: ['Membrane', 'Nucleus', 'DNA', 'ATP'],
        ),
      ],
    );
    await tester.pumpWidget(
      ThemeHarness(
        home: StudyPage(quiz: quiz, exporter: QuizPdfExporter()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Reveal answer'));
    await tester.tap(find.text('Reveal answer'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to dark theme'));
    await tester.pumpAndSettle();
    expect(find.text('ANSWER'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(StudyPage))).brightness,
      Brightness.dark,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Empty quiz can be repaired by adding a manual question', (
    tester,
  ) async {
    final quiz = SavedQuiz(
      id: 'empty',
      title: 'Biology',
      documentName: 'notes.txt',
      createdAt: DateTime(2026),
      mode: ExamMode.identification,
      questions: const [],
    );
    await tester.pumpWidget(ThemeHarness(home: ReviewPage(quiz: quiz)));
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save quiz'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Add question'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).at(0),
      'What protects a cell?',
    );
    await tester.enterText(find.byType(TextField).at(1), 'A membrane');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(find.text('What protects a cell?'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save quiz'))
          .onPressed,
      isNotNull,
    );
  });

  test('Both themes keep primary text and button contrast above 4.5:1', () {
    for (final brightness in Brightness.values) {
      final colors = buildAppTheme(brightness).colorScheme;
      for (final pair in [
        (colors.onSurface, colors.surfaceContainerLow),
        (colors.onPrimary, colors.primary),
        (colors.onPrimaryContainer, colors.primaryContainer),
      ]) {
        final values = [pair.$1.computeLuminance(), pair.$2.computeLuminance()]
          ..sort();
        expect(
          (values.last + .05) / (values.first + .05),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });
}
