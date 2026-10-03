import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revai/services/device_readiness.dart';
import 'package:revai/services/local_model_service.dart';
import 'package:revai/services/model_catalog.dart';
import 'package:revai/theme/app_theme.dart';
import 'package:revai/widgets/models_page.dart';

import 'support/fake_model_backend.dart';

class _ReadyDevice extends DeviceReadiness {
  int? requiredStorage;
  String? issue;

  @override
  Future<String?> checkForModelDownload({int requiredFreeBytes = 0}) async {
    requiredStorage = requiredFreeBytes;
    return issue;
  }
}

Widget _harness(LocalModelService model, _ReadyDevice device) => ThemeScope(
  setDarkMode: (_) {},
  child: MaterialApp(
    theme: buildAppTheme(Brightness.light),
    home: ModelsPage(model: model, deviceReadiness: device),
  ),
);

void main() {
  late FakeModelBackend backend;
  late LocalModelService service;
  late _ReadyDevice device;
  setUp(() {
    backend = FakeModelBackend();
    service = LocalModelService(
      backend: backend,
      preferences: MemoryModelPreferences(),
    );
    device = _ReadyDevice();
  });
  tearDown(() => service.dispose());

  testWidgets(
    'Download shows live progress, checks model storage, and can retry failure',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await service.initialize();
      backend.holdDownload = Completer<void>();
      backend.failDownloads = true;
      await tester.pumpWidget(_harness(service, device));
      await tester.tap(
        find.byKey(ValueKey('download-${localAiModels.first.id}')),
      );
      await tester.pump();
      await tester.pump();
      expect(device.requiredStorage, localAiModels.first.requiredFreeBytes);
      expect(find.text('Downloading · 45%'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(ValueKey('download-${localAiModels.last.id}')),
            )
            .onPressed,
        isNull,
      );
      backend.holdDownload!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Download did not finish.'), findsOneWidget);
      expect(service.selectedModel, isNull);
      backend.holdDownload = null;
      backend.failDownloads = false;
      await tester.tap(
        find.byKey(ValueKey('download-${localAiModels.first.id}')),
      );
      await tester.pumpAndSettle();
      expect(service.selectedModel, localAiModels.first);
      expect(find.textContaining('Download did not finish.'), findsNothing);
      expect(find.text('Selected'), findsOneWidget);
    },
  );

  testWidgets('Use model changes selection and removal requires confirmation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    backend.installed.addAll(localAiModels.map((model) => model.id));
    await service.initialize();
    await tester.pumpWidget(_harness(service, device));
    await tester.ensureVisible(
      find.byKey(ValueKey('select-${localAiModels.last.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('select-${localAiModels.last.id}')));
    await tester.pumpAndSettle();
    expect(service.selectedModel, localAiModels.last);
    await tester.ensureVisible(
      find.byTooltip('Remove ${localAiModels.last.name}'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove ${localAiModels.last.name}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(service.isDownloaded(localAiModels.last), isTrue);
    await tester.ensureVisible(
      find.byTooltip('Remove ${localAiModels.last.name}'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove ${localAiModels.last.name}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(service.isDownloaded(localAiModels.last), isFalse);
    expect(service.selectedModel, localAiModels.first);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Open chat disables model actions until native session cleanup', (
    tester,
  ) async {
    backend.installed.addAll(localAiModels.map((model) => model.id));
    await service.initialize();
    final chat = await service.createChatSession();
    await tester.pumpWidget(_harness(service, device));
    expect(find.textContaining('Finish or cancel quiz jobs'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(ValueKey('select-${localAiModels[1].id}')),
          )
          .onPressed,
      isNull,
    );
    await chat.close();
    await tester.pumpAndSettle();
    expect(find.textContaining('Finish or cancel quiz jobs'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(ValueKey('select-${localAiModels[1].id}')),
          )
          .onPressed,
      isNotNull,
    );
  });
}
