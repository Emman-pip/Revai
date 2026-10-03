# Features

## Home screen

The home screen gives chat and quiz creation equal prominence. It also shows the selected model and opens model management, alongside the saved quiz library and generation queue.

## Offline models

Download and select a local model from **Models**. The selected model is shared by chat and quiz generation and is remembered across launches. The app detects installed models, displays download progress, supports removal, and chooses an installed fallback if the selected model is removed. Downloads require internet access; inference runs on the device.

The catalog currently includes Gemma 4 E2B, Gemma 4 E4B, and Qwen3.5 0.8B. Each catalog entry provides a download URL, runtime model type, preferred backend, context size, and app-level quiz limits. The limits are surfaced during setup and checked before generation.

## AI chat

- Stream responses from the selected on-device model.
- Render Markdown, with a source-text view available for the original response.
- Stop an in-progress response while keeping its partial text.
- Start a new conversation or leave chat to clear the in-memory conversation.

## Document-based quizzes

Import PDF, DOCX, PPTX, Org, Markdown, or plain text. Import creates labeled sections such as PDF pages, presentation slides, or document paragraphs. Select all or part of the source, then configure title, destination folder, question type, total question count, and difficulty mix.

The setup screen keeps the question-type total and difficulty counts in sync as values change. Generated questions include source excerpts and locations when available. JSON output is syntax-checked, and validation feedback is sent to the model for up to three repair attempts. Valid questions are retained even when the model returns fewer than requested; add the missing questions manually in review.

## Quiz library and review

- Review and edit generated questions, answers, multiple-choice options, and source excerpts.
- Add or remove questions, including building a quiz draft manually.
- Study saved quizzes and track answers in the study flow.
- Organize quizzes into folders and move multiple quizzes together.
- Export a quiz PDF with an answer key.

## Generation queue

Quiz generation continues while the user navigates elsewhere in the app. Requests wait in a single-worker queue. Cancel a waiting job immediately or request cancellation of the active model call. Android notifications report generation stage and waiting count. If notification permission is unavailable, progress and cancellation remain in the app.

## Appearance and preferences

Choose light or dark appearance, or follow the device setting. Theme and model selection are persisted separately from quiz data.

## Document support limits

- Scanned PDFs and image-only slides need OCR; OCR is not currently supported.
- PPTX imports slide text in presentation order, including table text. Speaker notes, embedded files, and text within images are not imported.
- Plain text supports UTF-8 and UTF-16 with a byte-order mark.
- Markdown and Org headings are used as source labels. Markup is preserved as text; code blocks and directives are not executed.

See the [README](../README.md) for requirements, setup, model sizes, and development commands.
