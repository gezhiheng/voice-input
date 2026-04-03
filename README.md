# VoiceInput (macOS menu bar app)

VoiceInput is a macOS menu bar app that records speech while you hold **Fn**, transcribes it via Apple Speech, optionally refines the transcript via Alibaba Bailian `qwen-plus` (or another OpenAI-compatible LLM endpoint), and then pastes the final text into the active app.

## Requirements

- macOS 14+
- SwiftPM / Swift toolchain (see `Package.swift` for the pinned tools version)
- Xcode Command Line Tools (for `swift`, `codesign`, etc.)

## Develop

### Build + test (SwiftPM)

```bash
swift build
swift test
```

### Versioned release

The repository uses [`VERSION`](VERSION) as the single source of truth for app and release versions.

```bash
make release
```

This will:

- build the `.app`
- package it as `dist/VoiceInput-vX.Y.Z.zip`
- create or update the matching Git tag and GitHub release

On GitHub, `.github/workflows/release.yml` runs the same script automatically when `VERSION` changes on `main`.

### Run as a real `.app` bundle (recommended)

Running the app as a bundled `.app` is the most reliable way to validate permission prompts and menu-bar behavior.

```bash
make run
```

Build outputs go to `dist/` (ignored by git).

### Install locally

```bash
make install
```

Installs to `~/Applications/VoiceInput.app`.

### Clean

```bash
make clean
```

## Using the app (for testing behavior)

- Hold **Fn** to start recording; release **Fn** to stop and inject the final text.
- Use the menu bar icon to:
  - pick a language for the Speech recognizer
  - enable/disable LLM refinement and open LLM settings
  - toggle `Structured Rewrite` with `Command+S` from the top-level menu when you want the LLM to summarize and reorganize a long spoken draft
  - open the Permissions window

## Permissions (important for dev)

VoiceInput needs all of the following to work reliably:

- **Microphone**: record audio
- **Speech Recognition**: transcribe audio
- **Accessibility**: reliably synthesize paste events into the active app
- **Input Monitoring**: observe the **Fn** key globally (event tap)

The app shows a “Permissions…” window when requirements are missing. If you grant **Input Monitoring**, you may need to fully quit and reopen the app for the change to take effect.

When validating permission strings / prompts, use `make run` (or `make build` + open the `.app`) so the app has an `Info.plist` with the usage descriptions.

## LLM refinement (optional)

When enabled, VoiceInput sends the raw transcript to an **OpenAI-compatible** `chat/completions` endpoint with a conservative “correct recognition errors only” prompt tuned for Alibaba Bailian `qwen-plus`.

If `Structured Rewrite` is enabled from the top-level menu, VoiceInput switches to a different prompt that summarizes, distills, and reorganizes long spoken text into a clearer structure. This option is only selectable when LLM refinement is enabled and fully configured.

Configure via the menu bar:

- `LLM Refinement` → `Enabled`
- `LLM Refinement` → `Settings…`

Settings:

- **API Base URL**: defaults to Alibaba Bailian `https://dashscope.aliyuncs.com/compatible-mode/v1`, and also accepts a full path like `.../v1/chat/completions` (the app normalizes it)
- **API Key**: bearer token
- **Model**: defaults to `qwen-plus` (or any model your endpoint supports)

## Project layout

- `Sources/VoiceInputApp/*`: app code (one primary type per file)
- `Tests/VoiceInputAppTests/VoiceInputAppTests.swift`: `Testing`-based unit tests
- `Package.swift`: SwiftPM configuration
- `Makefile`: app bundling + signing into `dist/`
