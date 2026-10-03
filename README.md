# Revai

Revai turns PDF, DOCX, PPTX, Org mode, Markdown, and plain-text documents into a study quiz or printable exam. It is an Android-first Flutter app. Document text and generation stay on the device; the model is downloaded once and can then be used offline.

## Requirements

- Flutter 3.44+ and Dart 3.12+
- Android 12+ device, arm64, with at least 8 GB RAM
- About 3 GB free storage for Gemma 4 E2B, plus room for document and app data

## Run locally

```sh
flutter pub get
flutter run
```

The first launch can download **Gemma 4 E2B** (about 2.6 GB). An internet connection is needed for that download. Quiz creation then runs locally. The downloaded model is provided in LiteRT-LM format by the [LiteRT Community](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm) under Apache 2.0. The app runtime uses `flutter_gemma` and `flutter_gemma_litertlm`.

## Supported documents and quiz workflow

Supported files: `.pdf`, `.docx`, `.pptx`, `.org`, `.md`, and `.txt`. PPTX imports text from slides in presentation order, including text in tables; it does not import speaker notes, embedded files, or text inside images. Text files support UTF-8 and UTF-16 with a byte-order mark. Markdown and Org headings become source labels; source wording is preserved, including markup. Code blocks and directives are read as text and never executed. Scanned PDFs and image-only slides require OCR, which is not supported.

Choose multiple choice, identification, or hybrid mode, configure question and difficulty counts, optionally select source sections, and select a destination folder. Generation runs independently of navigation, so you can import another document or study a saved quiz while it works. Completed quizzes are saved automatically; use **Review** to edit them before studying or exporting. Answers include source excerpts with page, slide, paragraph, or line locations. Exported PDFs include an answer key.

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

Tests cover import ordering and encodings, legacy quiz migration, concurrent library writes, theme persistence and toggling, queued and active cancellation, and failure recovery. Device checks should include allowing/denying notifications, backgrounding a running job, cancelling it, and starting the next queued quiz.

## Local data

Saved quizzes and folders are stored in `quiz_library.json` in the app's private documents directory. Existing `saved_quizzes.json` data is read and migrated on the first library change. Writes are serialized and replaced atomically to preserve concurrent saves. Theme preferences are stored separately in `theme.json`. Removing a quiz deletes its saved record. The original source file is not copied into the quiz record.
