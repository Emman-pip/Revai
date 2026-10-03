# Repository Guidelines

## Project Structure

- `lib/models/` contains quiz and source-document data types.
- `lib/services/` handles document extraction, local model inference, quiz generation, storage, and PDF export.
- `lib/main.dart` contains the Flutter screens and user flow.
- `android/` contains the Android host project and Kotlin device-readiness bridge.

Keep platform-specific code in the relevant platform directory and keep document, model, and export logic in services rather than UI widgets.

## Build and Development

- `flutter pub get` resolves Dart and Flutter dependencies.
- `flutter run` launches the app on an attached device or configured emulator.
- `flutter build apk --release` creates `build/app/outputs/flutter-apk/app-release.apk` for local installation.
- `dart format lib` formats Dart source files.

The Android build targets Android 12+ and `arm64-v8a`. The app downloads Gemma 4 E2B on first setup; do not add model weights to the APK.

## Style and Naming

Use Dart's standard two-space indentation and `lower_snake_case.dart` filenames. Name Dart types in `UpperCamelCase` and members in `lowerCamelCase`. Keep widgets focused on presentation and move parsing, inference, validation, persistence, and PDF layout into services.

## Testing

There is no test suite yet. Add unit tests under `test/` for parsing, quiz validation, option ordering, persistence, and PDF generation as those services evolve. Run `flutter test` and `flutter analyze` when a change includes tests or a verification request.

## Contributions and Configuration

Use concise imperative commit subjects. Pull requests should summarize user-visible behavior and include device/build details for Android changes. Never commit local SDK paths, signing keys, credentials, uploaded documents, generated APKs, or model weights. Android SDK setup belongs in local SDK Manager configuration; `android/local.properties` is ignored.
