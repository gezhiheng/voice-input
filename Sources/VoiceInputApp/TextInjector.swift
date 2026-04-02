import ApplicationServices
import Foundation

final class TextInjector {
    private let clipboard: ClipboardManaging
    private let inputSourceManager: InputSourceManaging
    private let pastePerformer: () throws -> Void

    init(
        clipboard: ClipboardManaging,
        inputSourceManager: InputSourceManaging,
        pastePerformer: @escaping () throws -> Void = TextInjector.defaultPastePerformer
    ) {
        self.clipboard = clipboard
        self.inputSourceManager = inputSourceManager
        self.pastePerformer = pastePerformer
    }

    func inject(text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        let snapshot = clipboard.snapshot()
        let currentSource = inputSourceManager.currentInputSource()
        let originalSourceID = currentSource?.id
        let shouldSwitchToASCII = currentSource.map(InputSourceManager.isCJKSensitive) ?? false
        let asciiSourceID = shouldSwitchToASCII ? inputSourceManager.asciiCapableInputSource()?.id : nil

        do {
            try clipboard.replaceContents(with: trimmed)

            if let asciiSourceID, asciiSourceID != originalSourceID {
                _ = inputSourceManager.selectInputSource(withID: asciiSourceID)
                try await Task.sleep(nanoseconds: 80_000_000)
            }

            try pastePerformer()
            try await Task.sleep(nanoseconds: 120_000_000)

            if let originalSourceID, let asciiSourceID, asciiSourceID != originalSourceID {
                try await Task.sleep(nanoseconds: 80_000_000)
                _ = inputSourceManager.selectInputSource(withID: originalSourceID)
            }
        } catch {
            if let originalSourceID, let asciiSourceID, asciiSourceID != originalSourceID {
                _ = inputSourceManager.selectInputSource(withID: originalSourceID)
            }
            clipboard.restore(from: snapshot)
            throw error
        }

        clipboard.restore(from: snapshot)
    }

    static func defaultPastePerformer() throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw VoiceInputError.pasteSimulationFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
