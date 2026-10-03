# Revai

Revai provides offline AI chat and turns PDF, DOCX, PPTX, Org mode, Markdown, and plain-text documents into a study quiz or printable exam. It is an Android-first Flutter app. Chat, document text, and generation stay on the device. Download a local AI model once, then use it offline.

## Project documentation

- [Architecture](docs/architecture.md) — app layers, services, and data flows.
- [Features](docs/features.md) — user workflows and supported behavior.
- [Tech stack](docs/tech-stack.md) — runtime, packages, and platform requirements.

## Requirements

- Flutter 3.44+ and Dart 3.12+
- Android 12+ device, arm64, with at least 8 GB RAM
- Free storage for each downloaded model, plus at least 512 MB of headroom and room for document and app data

## Run locally

```sh
flutter pub get
flutter run
```

Open **Models** on the home screen to download and choose an AI model. An internet connection is needed for downloads; quiz creation and chat then run locally. The app runtime uses `flutter_gemma` and `flutter_gemma_litertlm`. Model weights are downloaded separately and are never bundled in the APK.

## Offline models and chat

| Model | Approximate download | Quiz limits |
| --- | --- | --- |
| [Gemma 4 E2B](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm) | 2.6 GB | 30 questions, 26,000 source characters |
| [Gemma 4 E4B](https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm) | 3.66 GB | 30 questions, 26,000 source characters |
| [Qwen3.5 0.8B](https://huggingface.co/litert-community/Qwen3.5-0.8B) | 963 MB | 5 questions, 6,000 source characters |

These LiteRT Community conversions are distributed under Apache 2.0. Qwen3.5 uses the CPU backend to avoid Android GPU compilation memory issues. The quiz limits are app limits; quality and speed depend on the model, source, and device. Source limits include the source labels added to the prompt.

The first successful download is selected automatically. To switch, tap **Use model** next to a downloaded model. One selection applies to both quizzes and chat, and is remembered across launches. Downloading additional models preserves your selection. **Remove** frees a downloaded model's storage after confirmation. Removing the selected model selects an installed Gemma E2B first, then another installed model, or leaves no selection if none remain. Saved quizzes are kept.

Finish or cancel queued quiz jobs and leave AI chat before downloading, selecting, or removing models. Existing Gemma E2B installations are recognized without another download.

Tap **Chat with AI** to start an offline conversation. Responses stream into a Markdown preview; **Source** shows the original Markdown and **Preview** restores rendering. Tap the stop button beside the prompt to cancel a reply while keeping its partial text. Chat has no fixed output token cap, but remains subject to the selected model's context window. **New chat** clears the conversation; leaving chat also clears it.

## Supported documents and quiz workflow

Supported files: `.pdf`, `.docx`, `.pptx`, `.org`, `.md`, and `.txt`. PPTX imports text from slides in presentation order, including text in tables; it does not import speaker notes, embedded files, or text inside images. Text files support UTF-8 and UTF-16 with a byte-order mark. Markdown and Org headings become source labels; source wording is preserved, including markup. Code blocks and directives are read as text and never executed. Scanned PDFs and image-only slides require OCR, which is not supported.

Choose multiple choice, identification, or hybrid mode, configure question and difficulty counts, optionally select source sections, and select a destination folder. Generation runs independently of navigation, so you can import another document or study a saved quiz while it works. Completed quizzes are saved automatically; use **Review** to edit them before studying or exporting. Answers include source excerpts with page, slide, paragraph, or line locations. Exported PDFs include an answer key.

### Edit a quiz manually

1. Tap **Review** on a completed job, or open a saved quiz's menu and choose **Review / edit**. If generation failed, use **Fix → Create manual draft**, then **Review**.
2. Open a question's menu and choose **Edit** to correct its wording, answer, options, or source excerpt. Choose **Remove** to discard it.
3. Tap **Add question** to fill gaps or build an empty draft. Enter a question and answer; for multiple choice, enter four distinct options and copy the correct option into **Correct answer**. Check answers against your original document.
4. Tap **Save** in the question editor, then **Save quiz** after finishing the review. An empty quiz needs at least one question before it can be saved from Review.

## Appearance and folders

Use the sun/moon button in the header to switch between light and dark themes. The app follows the device theme until you select a preference, then remembers that choice across launches.

Create folders in the quiz library. Long-press quizzes to select several, then use **Move selected quizzes** to group them. Individual quiz menus also support moving and editing. Rename or delete folders from their menu; deleting a folder moves its quizzes to **Ungrouped**.

## Generation queue and notifications

Multiple requests can wait in the queue while the interface stays usable. One local model processes one job at a time to avoid overlapping model sessions and excessive phone memory use. **Cancel** removes a waiting job or requests native cancellation of the current job; the next job starts after the model releases the cancelled session. Cancellation during model loading may wait for loading to return. Cancelled results are not saved. Saving a completed quiz is a short, non-cancellable step.

Android progress and completion notifications work offline. Allow notification permission when prompted to see them in the notification drawer. If denied, progress and cancellation remain available inside Revai. Notifications report generation stages and the waiting count, not an estimated percentage.

A foreground service and wake lock support generation while the app is backgrounded. Pending jobs are held in memory: force-stopping the app, removing its task, restarting the phone, or Android terminating the process can interrupt them. Completed quizzes remain saved. Android also limits long-running background services; interrupted requests must be submitted again.

## Checks

```sh
flutter --no-version-check analyze
flutter --no-version-check test
flutter --no-version-check build apk --release --target-platform android-arm64
```

Tests cover import ordering and encodings, legacy quiz migration, concurrent library writes, theme persistence and toggling, model selection and removal, download recovery, model-specific quiz limits, Markdown chat rendering, queued and active cancellation, and failure recovery. Device checks should include allowing/denying notifications, backgrounding a running job, cancelling it, starting the next queued quiz, and generating a quiz and chat reply with each downloaded model.

## Local data

Saved quizzes and folders are stored in `quiz_library.json` in the app's private documents directory. Existing `saved_quizzes.json` data is read and migrated on the first library change. Writes are serialized and replaced atomically to preserve concurrent saves. Theme preferences are stored separately in `theme.json`; model selection is stored in `model_preferences.json`. Removing a quiz deletes its saved record. The original source file is not copied into the quiz record.

## Source layout

- `lib/main.dart` — app startup, home screen, quiz setup, review, editing, and study screens.
- `lib/widgets/` — model management, chat, generation queue, and quiz library UI.
- `lib/services/` — document import, local inference, quiz generation and validation, storage, notifications, preferences, and PDF export.
- `lib/models/` — quiz, question, folder, and source-document data types.
- `lib/theme/` — shared app theme and color extensions.
- `android/` — Android host, device readiness bridge, and generation foreground service.
- `test/` — Flutter unit and widget tests.
