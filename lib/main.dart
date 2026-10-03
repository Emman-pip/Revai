import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';

import 'models/quiz.dart';
import 'services/document_importer.dart';
import 'services/device_readiness.dart';
import 'services/local_model_service.dart';
import 'services/quiz_generator.dart';
import 'services/quiz_pdf_exporter.dart';
import 'services/quiz_storage.dart';
import 'services/quiz_generation_queue.dart';
import 'widgets/generation_jobs_panel.dart';
import 'widgets/ai_chat_page.dart';
import 'widgets/quiz_library_browser.dart';
import 'services/theme_preferences.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  final preferences = ThemePreferences();
  final darkMode = await preferences.loadDarkMode();
  final model = LocalModelService();
  Object? modelInitError;
  try {
    await model.initialize();
  } catch (error) {
    modelInitError = error;
  }
  runApp(
    RevaiApp(
      model: model,
      modelInitError: modelInitError,
      preferences: preferences,
      initialThemeMode: darkMode == null
          ? ThemeMode.system
          : darkMode
          ? ThemeMode.dark
          : ThemeMode.light,
    ),
  );
}

class RevaiApp extends StatefulWidget {
  const RevaiApp({
    super.key,
    required this.model,
    this.modelInitError,
    required this.preferences,
    this.initialThemeMode = ThemeMode.system,
  });
  final LocalModelService model;
  final Object? modelInitError;
  final ThemePreferences preferences;
  final ThemeMode initialThemeMode;

  @override
  State<RevaiApp> createState() => _RevaiAppState();
}

class _RevaiAppState extends State<RevaiApp> {
  late ThemeMode mode = widget.initialThemeMode;
  final messenger = GlobalKey<ScaffoldMessengerState>();
  final storage = QuizStorage();
  late final queue = QuizGenerationQueue(
    generator: QuizGenerator(widget.model),
    storage: storage,
  );

  Future<void> _setDarkMode(bool dark) async {
    setState(() => mode = dark ? ThemeMode.dark : ThemeMode.light);
    try {
      await widget.preferences.saveDarkMode(dark);
    } catch (_) {
      messenger.currentState?.showSnackBar(
        const SnackBar(
          content: Text(
            'Theme changed, but your preference could not be saved.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ThemeScope(
    setDarkMode: _setDarkMode,
    child: MaterialApp(
      title: 'Revai',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: messenger,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: mode,
      home: HomePage(
        model: widget.model,
        modelInitError: widget.modelInitError,
        storage: storage,
        queue: queue,
      ),
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.model,
    this.modelInitError,
    required this.storage,
    required this.queue,
  });
  final QuizStorage storage;
  final QuizGenerationQueue queue;
  final LocalModelService model;
  final Object? modelInitError;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  QuizStorage get storage => widget.storage;
  final importer = DocumentImporter();
  final exporter = QuizPdfExporter();
  final deviceReadiness = DeviceReadiness();
  List<SavedQuiz> quizzes = [];
  List<QuizFolder> folders = [];
  bool isLoading = true;
  bool isPicking = false;
  bool isDownloading = false;
  int downloadProgress = 0;
  bool modelInstalled = false;
  String? operationError;

  @override
  void initState() {
    super.initState();
    storage.addListener(_reloadLibrary);
    _load();
  }

  @override
  void dispose() {
    storage.removeListener(_reloadLibrary);
    super.dispose();
  }

  Future<void> _reloadLibrary() async {
    try {
      final library = await storage.loadLibrary();
      if (mounted) {
        setState(() {
          quizzes = library.quizzes;
          folders = library.folders;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => operationError =
              'Could not load saved quizzes. ${_shortError(error)}',
        );
      }
    }
  }

  Future<void> _load() async {
    await _reloadLibrary();
    var installed = false;
    if (widget.modelInitError == null) {
      try {
        installed = await widget.model.isInstalled();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        modelInstalled = installed;
        isLoading = false;
      });
    }
  }

  Future<void> _pickDocument() async {
    setState(() {
      isPicking = true;
      operationError = null;
    });
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: DocumentImporter.supportedExtensions,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      final path = picked.path;
      if (path == null) {
        throw const DocumentImportException(
          'The selected file could not be opened.',
        );
      }
      final document = await importer.read(File(path), picked.name);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => SetupPage(
            document: document,
            model: widget.model,
            queue: widget.queue,
            folders: folders,
          ),
        ),
      );
    } on DocumentImportException catch (error) {
      if (!mounted) return;
      setState(() => operationError = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => operationError =
            'Could not read this document. ${_shortError(error)}',
      );
    } finally {
      if (mounted) setState(() => isPicking = false);
    }
  }

  Future<void> _downloadModel() async {
    setState(() {
      isDownloading = true;
      downloadProgress = 0;
      operationError = null;
    });
    try {
      final issue = await deviceReadiness.checkForModelDownload();
      if (issue != null) throw StateError(issue);
      await widget.model.download(
        onProgress: (progress) {
          if (mounted) setState(() => downloadProgress = progress);
        },
      );
      if (mounted) setState(() => modelInstalled = true);
    } catch (error) {
      if (mounted) {
        setState(
          () => operationError =
              'Model download did not finish. Check your connection and free storage, then retry. ${_shortError(error)}',
        );
      }
    } finally {
      if (mounted) setState(() => isDownloading = false);
    }
  }

  Future<void> _reviewQuiz(SavedQuiz quiz) async {
    final saved = (await storage.load())
        .where((item) => item.id == quiz.id)
        .firstOrNull;
    if (!mounted) return;
    if (saved == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This quiz has been deleted.')),
      );
      return;
    }
    final reviewed = await Navigator.of(context).push<SavedQuiz>(
      MaterialPageRoute(builder: (_) => ReviewPage(quiz: saved)),
    );
    if (reviewed != null) await storage.save(reviewed);
  }

  Future<void> _openStudy(SavedQuiz quiz) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudyPage(quiz: quiz, exporter: exporter),
      ),
    );
  }

  Future<void> _openChat() => Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => AiChatPage(model: widget.model)),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(22, 14, 22, 32),
                      sliver: SliverList.list(
                        children: [
                          _topBar(),
                          const SizedBox(height: 24),
                          _hero(),
                          const SizedBox(height: 18),
                          _modelCard(),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed:
                                modelInstalled && widget.modelInitError == null
                                ? _openChat
                                : null,
                            icon: const Icon(Icons.chat_bubble_outline_rounded),
                            label: const Text('Chat with AI'),
                          ),
                          if (!modelInstalled || widget.modelInitError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Download and set up the offline model to use chat.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          const SizedBox(height: 14),
                          GenerationJobsPanel(
                            queue: widget.queue,
                            onReview: _reviewQuiz,
                          ),
                          if (operationError != null) ...[
                            const SizedBox(height: 12),
                            _errorCard(operationError!),
                          ],
                          const SizedBox(height: 30),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Your quizzes',
                                  style: TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w800,
                                    color: context.colors.onSurface,
                                  ),
                                ),
                              ),
                              Text(
                                '${quizzes.length} saved',
                                style: TextStyle(
                                  color: context.colors.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          QuizLibraryBrowser(
                            quizzes: quizzes,
                            folders: folders,
                            storage: storage,
                            onOpen: _openStudy,
                            onReview: _reviewQuiz,
                            onExport: exporter.share,
                          ),
                          const SizedBox(height: 26),
                          Center(
                            child: Text(
                              'Your documents stay on this device',
                              style: TextStyle(
                                color: context.colors.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isPicking ? null : _pickDocument,
        backgroundColor: context.colors.primary,
        foregroundColor: context.colors.onPrimary,
        icon: isPicking
            ? SizedBox.square(
                dimension: 19,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.colors.onPrimary,
                ),
              )
            : const Icon(Icons.add_rounded),
        label: Text(isPicking ? 'Opening file…' : 'New quiz'),
      ),
    );
  }

  Widget _topBar() => Row(
    children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: context.colors.secondaryContainer,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(
          Icons.auto_awesome_rounded,
          color: context.colors.onSurface,
          size: 21,
        ),
      ),
      const SizedBox(width: 10),
      Text(
        'REVAI',
        style: TextStyle(
          letterSpacing: 2.2,
          fontWeight: FontWeight.w900,
          fontSize: 15,
          color: context.colors.onSurface,
        ),
      ),
      const Spacer(),
      const ThemeToggle(),
    ],
  );

  Widget _hero() => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: context.colors.primaryContainer,
      borderRadius: BorderRadius.circular(26),
    ),
    child: Stack(
      children: [
        Positioned(
          right: 0,
          top: 0,
          child: Icon(
            Icons.auto_stories_rounded,
            size: 88,
            color: context.colors.onPrimaryContainer.withValues(alpha: .08),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: context.colors.secondaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'STUDY, YOUR WAY',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 9,
                  letterSpacing: 1.1,
                  color: context.colors.onSecondaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 19),
            Text(
              'Turn reading\ninto remembering.',
              style: TextStyle(
                fontSize: 30,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: context.colors.onPrimaryContainer,
                letterSpacing: -.8,
              ),
            ),
            const SizedBox(height: 11),
            Text(
              'Build a study quiz from your own notes.',
              style: TextStyle(
                color: context.colors.onPrimaryContainer.withValues(alpha: .72),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: isPicking ? null : _pickDocument,
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: const Text('Choose a document'),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.onPrimaryContainer,
                side: BorderSide(
                  color: context.colors.onPrimaryContainer.withValues(
                    alpha: .35,
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 13,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _modelCard() {
    final error = widget.modelInitError;
    final available = modelInstalled && error == null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.colors.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              available ? Icons.memory_rounded : Icons.download_rounded,
              color: context.colors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  available ? 'AI model ready' : 'Set up offline AI',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: context.colors.onSurface,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  error != null
                      ? 'Model runtime could not initialize.'
                      : available
                      ? 'Gemma 4 E2B · available offline'
                      : isDownloading
                      ? 'Downloading model · $downloadProgress%'
                      : 'Gemma 4 E2B · one-time 2.6 GB download',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                if (isDownloading) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: downloadProgress == 0
                        ? null
                        : downloadProgress / 100,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (available)
            Icon(
              Icons.check_circle_rounded,
              color: context.colors.onSecondaryContainer,
            )
          else
            TextButton(
              onPressed: isDownloading || error != null ? null : _downloadModel,
              child: Text(isDownloading ? '$downloadProgress%' : 'Get model'),
            ),
        ],
      ),
    );
  }

  Widget _errorCard(String message) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.colors.errorContainer,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          color: context.colors.onErrorContainer,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: context.colors.onErrorContainer,
              fontSize: 12,
            ),
          ),
        ),
      ],
    ),
  );
}

class SetupPage extends StatefulWidget {
  const SetupPage({
    super.key,
    required this.document,
    required this.model,
    required this.queue,
    required this.folders,
  });
  final QuizGenerationQueue queue;
  final List<QuizFolder> folders;
  final SourceDocument document;
  final LocalModelService model;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  late final TextEditingController title;
  late final TextEditingController mcCount;
  late final TextEditingController idCount;
  late final TextEditingController easyCount;
  late final TextEditingController mediumCount;
  late final TextEditingController hardCount;
  ExamMode mode = ExamMode.hybrid;
  String? folderId;
  final Set<String> selectedSections = {};
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    title = TextEditingController(
      text: widget.document.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
    );
    mcCount = TextEditingController(text: '5');
    idCount = TextEditingController(text: '5');
    easyCount = TextEditingController(text: '3');
    mediumCount = TextEditingController(text: '4');
    hardCount = TextEditingController(text: '3');
  }

  @override
  void dispose() {
    title.dispose();
    mcCount.dispose();
    idCount.dispose();
    easyCount.dispose();
    mediumCount.dispose();
    hardCount.dispose();
    super.dispose();
  }

  int _value(TextEditingController controller) =>
      int.tryParse(controller.text) ?? 0;

  Future<void> _generate() async {
    final mc = mode == ExamMode.identification ? 0 : _value(mcCount);
    final id = mode == ExamMode.multipleChoice ? 0 : _value(idCount);
    final total = mc + id;
    if (total < 1 || total > 30) {
      setState(() => error = 'Choose between 1 and 30 questions.');
      return;
    }
    if (_value(easyCount) + _value(mediumCount) + _value(hardCount) != total) {
      setState(
        () => error = 'Easy, medium, and hard counts must add up to $total.',
      );
      return;
    }
    if ((mode == ExamMode.multipleChoice && mc < 1) ||
        (mode == ExamMode.identification && id < 1) ||
        (mode == ExamMode.hybrid && (mc < 1 || id < 1))) {
      setState(
        () => error = 'Hybrid mode needs at least one question of each type.',
      );
      return;
    }
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!await widget.model.isInstalled()) {
        throw StateError(
          'Download the offline model on the home screen before generating a quiz.',
        );
      }
      if (!mounted) return;
      final settings = QuizSettings(
        title: title.text,
        mode: mode,
        multipleChoiceCount: mc,
        identificationCount: id,
        easyCount: _value(easyCount),
        mediumCount: _value(mediumCount),
        hardCount: _value(hardCount),
        coverageIds: Set.of(selectedSections),
      );
      await widget.queue.enqueue(widget.document, settings, folderId: folderId);
      if (mounted) Navigator.of(context).pop();
    } catch (exception) {
      if (mounted) setState(() => error = _shortError(exception));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: const [ThemeToggle()],
      title: Text(
        'Build your quiz',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: context.colors.onSurface,
        ),
      ),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
        children: [
          _fileSummary(context, widget.document),
          const SizedBox(height: 21),
          _label(context, 'Quiz title'),
          TextField(
            controller: title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Give this quiz a name',
            ),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: '',
            decoration: const InputDecoration(labelText: 'Save to folder'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Ungrouped')),
              for (final folder in widget.folders)
                DropdownMenuItem(value: folder.id, child: Text(folder.name)),
            ],
            onChanged: (value) => folderId = value == '' ? null : value,
          ),
          const SizedBox(height: 20),
          _label(context, 'Question format'),
          const SizedBox(height: 9),
          Row(
            children: [
              _modeCard(
                ExamMode.multipleChoice,
                'Multiple choice',
                Icons.radio_button_checked_rounded,
              ),
              const SizedBox(width: 8),
              _modeCard(
                ExamMode.identification,
                'Identification',
                Icons.edit_note_rounded,
              ),
              const SizedBox(width: 8),
              _modeCard(ExamMode.hybrid, 'Hybrid', Icons.grid_view_rounded),
            ],
          ),
          const SizedBox(height: 20),
          _label(context, 'Question counts'),
          const SizedBox(height: 8),
          Row(
            children: [
              if (mode != ExamMode.identification)
                Expanded(child: _numberField('Multiple choice', mcCount)),
              if (mode == ExamMode.hybrid) const SizedBox(width: 9),
              if (mode != ExamMode.multipleChoice)
                Expanded(child: _numberField('Identification', idCount)),
            ],
          ),
          const SizedBox(height: 17),
          _label(context, 'Difficulty mix'),
          const SizedBox(height: 4),
          Text(
            'These counts must add up to ${mode == ExamMode.multipleChoice
                ? _value(mcCount)
                : mode == ExamMode.identification
                ? _value(idCount)
                : _value(mcCount) + _value(idCount)} questions.',
            style: TextStyle(
              color: context.colors.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _numberField('Easy', easyCount)),
              const SizedBox(width: 9),
              Expanded(child: _numberField('Medium', mediumCount)),
              const SizedBox(width: 9),
              Expanded(child: _numberField('Hard', hardCount)),
            ],
          ),
          const SizedBox(height: 20),
          _coveragePicker(),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.colors.secondaryContainer,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  color: context.colors.onSecondaryContainer,
                  size: 19,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Questions use your document only. Answers include their source location so you can check the original wording.',
                    style: TextStyle(
                      color: context.colors.onSurface,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 14),
            _inlineError(context, error!),
          ],
        ],
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        child: FilledButton.icon(
          onPressed: busy ? null : _generate,
          icon: busy
              ? SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.colors.onPrimary,
                  ),
                )
              : const Icon(Icons.auto_awesome_rounded),
          label: Text(busy ? 'Adding to queue…' : 'Generate in background'),
          style: FilledButton.styleFrom(
            backgroundColor: context.colors.primary,
            foregroundColor: context.colors.onPrimary,
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _modeCard(ExamMode value, String label, IconData icon) {
    final active = mode == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          mode = value;
          mcCount.text = value == ExamMode.identification
              ? '0'
              : value == ExamMode.hybrid
              ? '5'
              : '10';
          idCount.text = value == ExamMode.multipleChoice
              ? '0'
              : value == ExamMode.hybrid
              ? '5'
              : '10';
          easyCount.text = '3';
          mediumCount.text = '4';
          hardCount.text = '3';
        }),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 82,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: active
                ? context.colors.primaryContainer
                : context.colors.surfaceContainerLow,
            border: Border.all(
              color: active
                  ? context.colors.primary
                  : context.colors.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: active
                    ? context.colors.primary
                    : context.colors.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: active
                      ? context.colors.onSurface
                      : context.colors.onSurfaceVariant,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coveragePicker() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _label(context, 'Document coverage'),
      const SizedBox(height: 4),
      Text(
        'Leave all unselected to include the whole document.',
        style: TextStyle(fontSize: 11, color: context.colors.onSurfaceVariant),
      ),
      const SizedBox(height: 8),
      Container(
        constraints: const BoxConstraints(maxHeight: 150),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerLow,
          border: Border.all(color: context.colors.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              for (final section in widget.document.sections)
                FilterChip(
                  label: Text(
                    section.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: selectedSections.contains(section.id),
                  onSelected: (selected) => setState(
                    () => selected
                        ? selectedSections.add(section.id)
                        : selectedSections.remove(section.id),
                  ),
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(fontSize: 10),
                ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _numberField(String label, TextEditingController controller) =>
      TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
        ),
      );
}

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.quiz});
  final SavedQuiz quiz;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late List<QuizQuestion> questions;

  @override
  void initState() {
    super.initState();
    questions = [...widget.quiz.questions];
  }

  Future<void> _edit(int index) async {
    final changed = await showDialog<QuizQuestion>(
      context: context,
      builder: (_) => EditQuestionDialog(question: questions[index]),
    );
    if (changed != null) setState(() => questions[index] = changed);
  }

  Future<void> _addQuestion() async {
    final question = await showDialog<QuizQuestion>(
      context: context,
      builder: (_) => const EditQuestionDialog(),
    );
    if (question != null) setState(() => questions.add(question));
  }

  void _finish() {
    final hasMc = questions.any((q) => q.kind == QuestionKind.multipleChoice);
    final hasId = questions.any((q) => q.kind == QuestionKind.identification);
    final mode = hasMc && hasId
        ? ExamMode.hybrid
        : hasMc
        ? ExamMode.multipleChoice
        : ExamMode.identification;
    final quiz = SavedQuiz(
      id: widget.quiz.id,
      title: widget.quiz.title,
      documentName: widget.quiz.documentName,
      createdAt: widget.quiz.createdAt,
      mode: mode,
      questions: questions,
      folderId: widget.quiz.folderId,
    );
    Navigator.of(context).pop(quiz);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: const [ThemeToggle()],
      title: Text(
        'Review questions',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: context.colors.onSurface,
        ),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 3, 20, 24),
      children: [
        Text(
          '${questions.length} questions · ${widget.quiz.documentName}',
          style: TextStyle(
            color: context.colors.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Check each generated answer against the source. Use Edit to correct a question, Remove to discard it, or Add question to fill gaps.',
          style: TextStyle(
            color: context.colors.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _addQuestion,
            icon: const Icon(Icons.add),
            label: const Text('Add question'),
          ),
        ),
        for (var i = 0; i < questions.length; i++) _reviewCard(i),
        if (questions.isEmpty)
          _inlineError(
            context,
            'No questions were generated. Add one manually to continue.',
          ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        child: FilledButton.icon(
          onPressed: questions.isEmpty ? null : _finish,
          icon: const Icon(Icons.menu_book_rounded),
          label: const Text('Save quiz'),
          style: FilledButton.styleFrom(
            backgroundColor: context.colors.primary,
            foregroundColor: context.colors.onPrimary,
            minimumSize: const Size.fromHeight(54),
          ),
        ),
      ),
    ),
  );

  Widget _reviewCard(int index) {
    final q = questions[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        border: Border.all(color: context.colors.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'QUESTION ${(index + 1).toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: context.colors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                q.kind == QuestionKind.multipleChoice
                    ? 'MCQ'
                    : 'IDENTIFICATION',
                style: TextStyle(
                  color: context.colors.onSurfaceVariant,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') _edit(index);
                  if (value == 'remove') {
                    setState(() => questions.removeAt(index));
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'remove', child: Text('Remove')),
                ],
              ),
            ],
          ),
          Text(
            q.prompt,
            style: TextStyle(
              color: context.colors.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          if (q.kind == QuestionKind.multipleChoice) ...[
            const SizedBox(height: 8),
            for (var i = 0; i < q.options.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '${String.fromCharCode(65 + i)}. ${q.options[i]}',
                  style: TextStyle(
                    color: context.colors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SOURCE · ${q.sourceLabel.toUpperCase()}',
                  style: TextStyle(
                    color: context.colors.onSurfaceVariant,
                    fontSize: 9,
                    letterSpacing: .6,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '“${q.sourceExcerpt}”',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.onSurface,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class EditQuestionDialog extends StatefulWidget {
  const EditQuestionDialog({super.key, this.question});
  final QuizQuestion? question;
  @override
  State<EditQuestionDialog> createState() => _EditQuestionDialogState();
}

class _EditQuestionDialogState extends State<EditQuestionDialog> {
  late final TextEditingController prompt;
  late final TextEditingController answer;
  late final TextEditingController sourceExcerpt;
  late final List<TextEditingController> options;
  late QuestionKind kind;
  String? validationError;

  @override
  void initState() {
    super.initState();
    final question = widget.question;
    kind = question?.kind ?? QuestionKind.identification;
    prompt = TextEditingController(text: question?.prompt ?? '');
    answer = TextEditingController(text: question?.answer ?? '');
    sourceExcerpt = TextEditingController(text: question?.sourceExcerpt ?? '');
    options = [
      for (var i = 0; i < (question?.options.length ?? 0); i++)
        TextEditingController(text: question!.options[i]),
    ];
    if (kind == QuestionKind.multipleChoice && options.length < 4) {
      while (options.length < 4) {
        options.add(TextEditingController());
      }
    }
    if (options.length > 4) options.removeRange(4, options.length);
  }

  @override
  void dispose() {
    prompt.dispose();
    answer.dispose();
    sourceExcerpt.dispose();
    for (final option in options) {
      option.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit question'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<QuestionKind>(
            initialValue: kind,
            decoration: const InputDecoration(labelText: 'Question type'),
            items: const [
              DropdownMenuItem(
                value: QuestionKind.identification,
                child: Text('Identification'),
              ),
              DropdownMenuItem(
                value: QuestionKind.multipleChoice,
                child: Text('Multiple choice'),
              ),
            ],
            onChanged: (value) => setState(() {
              kind = value ?? QuestionKind.identification;
              if (kind == QuestionKind.multipleChoice) {
                while (options.length < 4) {
                  options.add(TextEditingController());
                }
                if (options.length > 4) {
                  options.removeRange(4, options.length);
                }
              }
            }),
          ),
          TextField(
            controller: prompt,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Question'),
          ),
          const SizedBox(height: 8),
          if (kind == QuestionKind.multipleChoice)
            for (var i = 0; i < options.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: TextField(
                  controller: options[i],
                  decoration: InputDecoration(
                    labelText: 'Option ${String.fromCharCode(65 + i)}',
                  ),
                ),
              ),
          TextField(
            controller: answer,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Correct answer'),
          ),
          TextField(
            controller: sourceExcerpt,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Source excerpt (optional)',
            ),
          ),
          if (validationError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                validationError!,
                style: TextStyle(color: context.colors.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (prompt.text.trim().isEmpty || answer.text.trim().isEmpty) {
            setState(
              () =>
                  validationError = 'Enter a question and its correct answer.',
            );
            return;
          }
          final updatedOptions = [
            for (final option in options) option.text.trim(),
          ];
          if (kind == QuestionKind.multipleChoice) {
            final cleaned = updatedOptions
                .where((value) => value.isNotEmpty)
                .toList();
            if (cleaned.length != 4 || cleaned.toSet().length != 4) {
              setState(
                () => validationError = 'Enter four distinct answer options.',
              );
              return;
            }
            final oldQuestion = widget.question;
            final oldIndex =
                oldQuestion?.options.indexOf(oldQuestion.answer) ?? -1;
            if (!updatedOptions.contains(answer.text.trim())) {
              updatedOptions[oldIndex >= 0 && oldIndex < 4 ? oldIndex : 0] =
                  answer.text.trim();
            }
            if (updatedOptions.toSet().length != 4) {
              setState(
                () => validationError =
                    'Keep all four options distinct after setting the answer.',
              );
              return;
            }
          }
          final oldQuestion = widget.question;
          Navigator.pop(
            context,
            (oldQuestion ??
                    QuizQuestion(
                      id: DateTime.now().microsecondsSinceEpoch.toString(),
                      kind: kind,
                      prompt: '',
                      answer: '',
                      sourceId: 'manual',
                      sourceLabel: 'Manual entry',
                      sourceExcerpt: '',
                    ))
                .copyWith(
                  kind: kind,
                  prompt: prompt.text.trim(),
                  answer: answer.text.trim(),
                  sourceExcerpt: sourceExcerpt.text.trim(),
                  options: kind == QuestionKind.multipleChoice
                      ? updatedOptions
                      : const [],
                ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class StudyPage extends StatefulWidget {
  const StudyPage({super.key, required this.quiz, required this.exporter});
  final SavedQuiz quiz;
  final QuizPdfExporter exporter;
  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  int current = 0;
  bool showAnswer = false;
  String? selected;

  @override
  Widget build(BuildContext context) {
    final question = widget.quiz.questions[current];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.quiz.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: context.colors.onSurface,
          ),
        ),
        actions: [
          const ThemeToggle(),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'share') await widget.exporter.share(widget.quiz);
              if (value == 'print') {
                final bytes = await widget.exporter.build(widget.quiz);
                await Printing.layoutPdf(onLayout: (_) async => bytes);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'share', child: Text('Share quiz PDF')),
              PopupMenuItem(value: 'print', child: Text('Print / save PDF')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Row(
              children: [
                Text(
                  'QUESTION ${current + 1} OF ${widget.quiz.questions.length}',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w900,
                    color: context.colors.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  question.difficulty.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    color: context.colors.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: (current + 1) / widget.quiz.questions.length,
                minHeight: 6,
                color: context.colors.primary,
                backgroundColor: context.colors.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(21),
              decoration: BoxDecoration(
                color: context.colors.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      question.kind == QuestionKind.multipleChoice
                          ? 'MULTIPLE CHOICE'
                          : 'IDENTIFICATION',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8,
                        color: context.colors.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    question.prompt,
                    style: TextStyle(
                      color: context.colors.onPrimaryContainer,
                      fontSize: 22,
                      height: 1.28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 17),
            if (question.kind == QuestionKind.multipleChoice) ...[
              for (var i = 0; i < question.options.length; i++)
                _answerOption(question, i),
            ] else
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerLow,
                  border: Border.all(color: context.colors.outlineVariant),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextField(
                  onChanged: (value) => selected = value,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Type your answer (optional)',
                    border: InputBorder.none,
                    fillColor: Colors.transparent,
                  ),
                ),
              ),
            const SizedBox(height: 14),
            if (!showAnswer)
              FilledButton(
                onPressed: () => setState(() => showAnswer = true),
                style: FilledButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  foregroundColor: context.colors.onPrimary,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Text('Reveal answer'),
              )
            else
              _revealed(question),
            const SizedBox(height: 20),
            Row(
              children: [
                TextButton.icon(
                  onPressed: current == 0
                      ? null
                      : () => setState(() {
                          current--;
                          showAnswer = false;
                          selected = null;
                        }),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Previous'),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: current == widget.quiz.questions.length - 1
                      ? null
                      : () => setState(() {
                          current++;
                          showAnswer = false;
                          selected = null;
                        }),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _answerOption(QuizQuestion q, int index) {
    final value = q.options[index];
    final isSelected = selected == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: showAnswer ? null : () => setState(() => selected = value),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: isSelected
                ? context.colors.primaryContainer
                : context.colors.surfaceContainerLow,
            border: Border.all(
              color: isSelected
                  ? context.colors.primary
                  : context.colors.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 27,
                height: 27,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? context.colors.primary
                      : context.colors.surface,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  String.fromCharCode(65 + index),
                  style: TextStyle(
                    color: isSelected
                        ? context.colors.onPrimary
                        : context.colors.onSurface,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    color: context.colors.onSurface,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle_rounded,
                  color: context.colors.primary,
                  size: 19,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _revealed(QuizQuestion question) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.colors.secondaryContainer,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ANSWER',
          style: TextStyle(
            color: context.colors.onSecondaryContainer,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          question.answer,
          style: TextStyle(
            color: context.colors.onSurface,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
        if (question.explanation.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            question.explanation,
            style: TextStyle(
              color: context.colors.onSurface,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
        const Divider(height: 22),
        Text(
          'SOURCE · ${question.sourceLabel}',
          style: TextStyle(
            color: context.colors.onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '“${question.sourceExcerpt}”',
          style: TextStyle(
            color: context.colors.onSurface,
            fontSize: 11,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

Widget _fileSummary(BuildContext context, SourceDocument document) => Container(
  padding: const EdgeInsets.all(13),
  decoration: BoxDecoration(
    color: context.colors.surfaceContainerLow,
    borderRadius: BorderRadius.circular(17),
    border: Border.all(color: context.colors.outlineVariant),
  ),
  child: Row(
    children: [
      Icon(Icons.description_outlined, color: context.colors.primary),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              document.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.colors.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            Text(
              '${document.sections.length} text sections',
              style: TextStyle(
                color: context.colors.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    ],
  ),
);
Widget _label(BuildContext context, String text) => Text(
  text,
  style: TextStyle(
    color: context.colors.onSurface,
    fontSize: 13,
    fontWeight: FontWeight.w800,
  ),
);
Widget _inlineError(BuildContext context, String text) => Container(
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: context.colors.errorContainer,
    borderRadius: BorderRadius.circular(13),
  ),
  child: Text(
    text,
    style: TextStyle(color: context.colors.onErrorContainer, fontSize: 12),
  ),
);
String _shortError(Object error) => error
    .toString()
    .replaceFirst('Exception: ', '')
    .replaceFirst('Bad state: ', '');
