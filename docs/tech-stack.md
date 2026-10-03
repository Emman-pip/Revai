# Tech stack

## Languages and platform

- **Dart and Flutter** for the cross-platform UI, domain models, app services, and tests.
- **Kotlin and Android APIs** for the Android host, device readiness bridge, and generation foreground service.
- **Android 12+**, targeting `arm64-v8a` for on-device model inference.

The app requires Flutter 3.44+ and Dart 3.12+ (see the SDK constraints in `pubspec.yaml`). Model files are downloaded at runtime and are not packaged into the APK.

## Main packages

| Package | Use in Revai |
| --- | --- |
| `flutter_gemma`, `flutter_gemma_litertlm` | Local model installation, model loading, chat, and token generation through the LiteRT-LM runtime. |
| `file_picker` | Select source documents from the device. |
| `pdfrx` | Extract selectable text from PDF pages. |
| `archive` | Read DOCX and PPTX ZIP containers. |
| `xml` | Parse document XML, presentation relationships, and slide/paragraph content. |
| `path_provider` | Locate app-private directories for saved data and preferences. |
| `pdf`, `printing` | Build and share or save quiz PDFs. |
| `flutter_markdown_plus` | Render model responses as Markdown in chat. |
| `flutter_test`, `flutter_lints` | Widget/unit testing and lint rules. |

See `pubspec.yaml` for the version constraints and `pubspec.lock` for the resolved package versions.

## App-specific interfaces

- `LocalModelBackend` isolates the model service from the concrete inference SDK and allows a fake backend in tests.
- `QuizGenerator` constructs prompts, validates generated JSON, retries invalid output, parses questions, and balances multiple-choice options.
- `QuizGenerationQueue` serializes quiz work, tracks job status, and coordinates cancellation and notifications.
- `DocumentImporter` converts supported formats into a common `SourceDocument` structure.
- `QuizStorage`, `ThemePreferences`, and `ModelPreferences` handle local persistence.

## Android integration

Flutter method channels connect Dart services to Kotlin for device memory and available-storage checks and generation service/notification control. Android's WorkManager foreground service declaration is merged for model downloads. The generation foreground service and wake lock support active jobs while backgrounded.

## Local development

```sh
flutter pub get
flutter run
flutter --no-version-check analyze
flutter --no-version-check test
flutter --no-version-check build apk --release --target-platform android-arm64
```
