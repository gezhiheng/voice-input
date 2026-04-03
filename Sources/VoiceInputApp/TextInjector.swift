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

        let initialState = await MainActor.run { () -> (PasteboardSnapshot, String?, String?) in
            let snapshot = clipboard.snapshot()
            let currentSource = inputSourceManager.currentInputSource()
            let originalSourceID = currentSource?.id
            let shouldSwitchToASCII = currentSource.map(InputSourceManager.isCJKSensitive) ?? false
            let asciiSourceID = shouldSwitchToASCII ? inputSourceManager.asciiCapableInputSource()?.id : nil
            return (snapshot, originalSourceID, asciiSourceID)
        }

        let snapshot = initialState.0
        let originalSourceID = initialState.1
        let asciiSourceID = initialState.2

        do {
            try await MainActor.run {
                try clipboard.replaceContents(with: trimmed)
            }

            if let asciiSourceID, asciiSourceID != originalSourceID {
                await MainActor.run {
                    _ = inputSourceManager.selectInputSource(withID: asciiSourceID)
                }
                try await Task.sleep(nanoseconds: 80_000_000)
            }

            try pastePerformer()
            try await Task.sleep(nanoseconds: 120_000_000)

            if let originalSourceID, let asciiSourceID, asciiSourceID != originalSourceID {
                try await Task.sleep(nanoseconds: 80_000_000)
                await MainActor.run {
                    _ = inputSourceManager.selectInputSource(withID: originalSourceID)
                }
            }
        } catch {
            if let originalSourceID, let asciiSourceID, asciiSourceID != originalSourceID {
                await MainActor.run {
                    _ = inputSourceManager.selectInputSource(withID: originalSourceID)
                }
            }
            await MainActor.run {
                clipboard.restore(from: snapshot)
            }
            throw error
        }

        await MainActor.run {
            clipboard.restore(from: snapshot)
        }
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
