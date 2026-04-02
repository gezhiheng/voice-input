# Repository Guidelines

## Project Structure & Module Organization
This repository is a Swift Package for a macOS menu bar app. Application code lives in `Sources/VoiceInputApp`, with one primary type per file such as `SettingsStore.swift`, `RecordingCoordinator.swift`, and `LLMRefiner.swift`. Tests live in `Tests/VoiceInputAppTests` and currently use a single `VoiceInputAppTests.swift` file. Build and app-bundling logic is defined in `Package.swift` and `Makefile`. Generated app bundles are written to `dist/` and should not be committed.

## Build, Test, and Development Commands
Use SwiftPM for compile and test loops:

- `swift build` builds the executable target in debug mode.
- `swift test` runs the `Testing`-based test suite.
- `make build` creates a signed macOS `.app` bundle in `dist/`.
- `make run` builds the app bundle and opens it.
- `make install` copies the built app into `~/Applications`.
- `make clean` removes `.build/` and `dist/`.

Run `swift test` before opening a PR. Use `make build` when you need to verify bundle metadata, permissions strings, or app-launch behavior.

## Coding Style & Naming Conventions
Follow the existing Swift style in `Sources/VoiceInputApp`: 4-space indentation, one top-level type per file, and `UpperCamelCase` for types with `lowerCamelCase` for methods and properties. Prefer small, focused classes and structs that map directly to app responsibilities. Keep imports minimal and preserve `@MainActor` annotations where UI or settings state is actor-bound.

## Testing Guidelines
Tests use Apple’s `Testing` package with `@Test` functions and `#expect(...)` assertions. Name tests for behavior, for example `llmEndpointNormalizationHandlesBaseAndFullEndpoint`. Add tests alongside the feature you change, especially for settings persistence, text injection, input-source handling, and LLM endpoint normalization. Run `swift test` locally before submitting changes.

## Commit & Pull Request Guidelines
There is no established Git history yet, so use clear Conventional Commit-style messages such as `feat: add Korean input-source fallback` or `fix: preserve clipboard restore order`. Keep commits scoped to one change. PRs should include a short summary, test notes, and screenshots or screen recordings for UI-visible changes like the floating panel, settings window, or permission flows.

## Security & Configuration Tips
Do not commit real API keys, signing identities, or local `UserDefaults` data. The app requests microphone and speech-recognition access; validate permission-related changes with the bundled app created by `make build`.
