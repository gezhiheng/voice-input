import Combine
import Foundation

@MainActor
final class RecordingCoordinator: ObservableObject {
    @Published private(set) var phase: RecordingPhase = .idle

    private let settingsStore: SettingsStore
    private let permissionsCoordinator: PermissionsCoordinator
    private let speechRecognizer: SpeechTranscribing
    private let panelController: FloatingPanelController
    private let textInjector: TextInjector
    private let textRefiner: TextRefining
    private let showPermissionsWindow: () -> Void

    private var isFnPressed = false
    private var isHandlingSession = false
    private var latestTranscript = ""

    init(
        settingsStore: SettingsStore,
        permissionsCoordinator: PermissionsCoordinator,
        speechRecognizer: SpeechTranscribing,
        panelController: FloatingPanelController,
        textInjector: TextInjector,
        textRefiner: TextRefining,
        showPermissionsWindow: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.permissionsCoordinator = permissionsCoordinator
        self.speechRecognizer = speechRecognizer
        self.panelController = panelController
        self.textInjector = textInjector
        self.textRefiner = textRefiner
        self.showPermissionsWindow = showPermissionsWindow
    }

    func handleFnPressed() {
        guard !isFnPressed else {
            return
        }

        isFnPressed = true

        Task {
            await beginRecording()
        }
    }

    func handleFnReleased() {
        guard isFnPressed else {
            return
        }

        isFnPressed = false

        Task {
            await finalizeRecording()
        }
    }

    func cancel() {
        speechRecognizer.cancel()
        panelController.dismiss()
        latestTranscript = ""
        phase = .idle
        isHandlingSession = false
        isFnPressed = false
    }

    private func beginRecording() async {
        guard !isHandlingSession else {
            return
        }

        permissionsCoordinator.refresh()

        guard permissionsCoordinator.snapshot.allRequiredGranted else {
            showPermissionsWindow()
            phase = .error("Permissions required")
            panelController.showStatus("Grant permissions first")
            try? await Task.sleep(nanoseconds: 900_000_000)
            panelController.dismiss()
            phase = .idle
            return
        }

        isHandlingSession = true
        latestTranscript = ""
        phase = .listening
        panelController.showListening()

        do {
            try await speechRecognizer.start(
                locale: settingsStore.settings.selectedLanguage.locale,
                partialHandler: { [weak self] text in
                    Task { @MainActor in
                        guard let self, self.phase == .listening else {
                            return
                        }
                        self.latestTranscript = text
                        self.panelController.updateTranscript(text)
                    }
                },
                levelHandler: { [weak self] levels in
                    Task { @MainActor in
                        guard let self, self.phase == .listening else {
                            return
                        }
                        self.panelController.updateWaveform(levels)
                    }
                }
            )
        } catch {
            await presentError(error.localizedDescription)
        }
    }

    private func finalizeRecording() async {
        guard isHandlingSession, phase == .listening else {
            return
        }

        let transcript: String
        do {
            transcript = try await speechRecognizer.stop()
        } catch {
            await presentError(error.localizedDescription)
            return
        }

        latestTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !latestTranscript.isEmpty else {
            panelController.dismiss()
            phase = .idle
            isHandlingSession = false
            return
        }

        var finalText = latestTranscript
        let llmSettings = settingsStore.settings

        if llmSettings.llmEnabled && llmSettings.llmConfiguration.isConfigured {
            phase = .refining
            panelController.showRefining()

            do {
                finalText = try await textRefiner.refine(
                    latestTranscript,
                    configuration: llmSettings.llmConfiguration,
                    mode: llmSettings.llmRefinementMode
                )
            } catch {
                panelController.showStatus("LLM unavailable, using raw text…")
                try? await Task.sleep(nanoseconds: 600_000_000)
                finalText = latestTranscript
            }
        }

        guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            panelController.dismiss()
            phase = .idle
            isHandlingSession = false
            return
        }

        phase = .injecting

        do {
            try await textInjector.inject(text: finalText)
            panelController.dismiss()
            phase = .idle
            isHandlingSession = false
        } catch {
            await presentError(error.localizedDescription)
        }
    }

    private func presentError(_ message: String) async {
        phase = .error(message)
        speechRecognizer.cancel()
        panelController.showStatus(message)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        panelController.dismiss()
        phase = .idle
        latestTranscript = ""
        isHandlingSession = false
    }
}
