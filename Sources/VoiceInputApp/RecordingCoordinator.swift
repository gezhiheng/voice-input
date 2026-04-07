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

    private var isHandlingSession = false
    private var isRecording = false
    private var latestTranscript = ""
    private var lastTranscriptUpdateTime: Date?
    private var silenceCheckTask: Task<Void, Never>?
    private static let silenceThreshold: TimeInterval = 2.5

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

    func toggleRecording() {
        if isRecording {
            Task {
                await finalizeRecording()
            }
        } else {
            Task {
                await beginRecording()
            }
        }
    }

    func cancel() {
        stopSilenceCheck()
        speechRecognizer.cancel()
        panelController.dismiss()
        latestTranscript = ""
        lastTranscriptUpdateTime = nil
        phase = .idle
        isHandlingSession = false
        isRecording = false
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
        isRecording = true
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
                        self.lastTranscriptUpdateTime = Date()
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
            
            // 启动静音检测
            startSilenceCheck()
        } catch {
            await presentError(error.localizedDescription)
        }
    }

    private func finalizeRecording() async {
        guard isHandlingSession, phase == .listening else {
            return
        }

        isRecording = false
        stopSilenceCheck()

        // 保存静音检测前已有的转写内容（作为后备）
        let existingTranscript = latestTranscript

        let transcript: String
        do {
            transcript = try await speechRecognizer.stop()
        } catch {
            await presentError(error.localizedDescription)
            return
        }

        // 如果 stop() 返回了有效内容，使用它；否则保留静音检测前已有的内容
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTranscript.isEmpty {
            latestTranscript = trimmedTranscript
        } else if !existingTranscript.isEmpty {
            // 保留静音检测前已有的转写内容
            latestTranscript = existingTranscript
        }
        lastTranscriptUpdateTime = nil

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
        stopSilenceCheck()
        phase = .error(message)
        speechRecognizer.cancel()
        panelController.showStatus(message)
        isRecording = false
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        panelController.dismiss()
        phase = .idle
        latestTranscript = ""
        lastTranscriptUpdateTime = nil
        isHandlingSession = false
    }
    
    // MARK: - Silence Detection
    
    private func startSilenceCheck() {
        stopSilenceCheck()
        lastTranscriptUpdateTime = Date()
        
        silenceCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms 检查一次
                
                guard let self = self else { return }
                
                // 必须在主线程访问状态
                await MainActor.run {
                    guard self.isHandlingSession,
                          self.phase == .listening,
                          let lastUpdate = self.lastTranscriptUpdateTime else {
                        return
                    }
                    
                    let elapsed = Date().timeIntervalSince(lastUpdate)
                    if elapsed >= Self.silenceThreshold {
                        // 静音超时，自动完成录音
                        // 必须先标记，防止后续检查再次触发
                        self.stopSilenceCheck()
                        self.lastTranscriptUpdateTime = nil
                        Task { [weak self] in
                            await self?.finalizeRecording()
                        }
                    }
                }
            }
        }
    }
    
    private func stopSilenceCheck() {
        silenceCheckTask?.cancel()
        silenceCheckTask = nil
    }
}
