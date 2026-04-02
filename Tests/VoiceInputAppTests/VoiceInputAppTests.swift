import Foundation
import Testing
@testable import VoiceInputApp

@Test
func defaultLanguageIsSimplifiedChinese() {
    #expect(AppSettings.default.selectedLanguage == .simplifiedChinese)
}

@Test
func settingsStorePersistsLanguageAndClearsAPIKey() async throws {
    let suiteName = "VoiceInputAppTests-\(UUID().uuidString)"

    await MainActor.run {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)
        #expect(store.settings.selectedLanguage == .simplifiedChinese)

        store.updateLanguage(.japanese)
        store.save(configuration: .init(baseURL: "https://example.com/v1", apiKey: "", model: "gpt-test"))

        #expect(store.settings.selectedLanguage == .japanese)
        #expect(store.settings.llmConfiguration.apiKey == "")
        #expect(defaults.string(forKey: "llmAPIKey") == "")
    }
}

@Test
func llmEndpointNormalizationHandlesBaseAndFullEndpoint() throws {
    let refiner = LLMRefiner(session: URLSession(configuration: .ephemeral))

    let base = try refiner.normalizedEndpoint(from: "https://api.openai.com/v1")
    #expect(base.absoluteString == "https://api.openai.com/v1/chat/completions")

    let full = try refiner.normalizedEndpoint(from: "https://example.com/custom/chat/completions")
    #expect(full.absoluteString == "https://example.com/custom/chat/completions")

    let root = try refiner.normalizedEndpoint(from: "https://example.com")
    #expect(root.absoluteString == "https://example.com/v1/chat/completions")
}

@Test
func cjkInputSourceDetectionMatchesLanguagesAndInputMethods() {
    let chinese = InputSourceDescriptor(id: "zh", languages: ["zh-Hans"], sourceType: "TISTypeKeyboardInputMethodModeEnabled", isASCII: false)
    #expect(InputSourceManager.isCJKSensitive(chinese))

    let korean = InputSourceDescriptor(id: "ko", languages: ["ko"], sourceType: "TISTypeKeyboardInputMethodWithoutModes", isASCII: false)
    #expect(InputSourceManager.isCJKSensitive(korean))

    let english = InputSourceDescriptor(id: "us", languages: ["en"], sourceType: "TISTypeKeyboardLayout", isASCII: true)
    #expect(!InputSourceManager.isCJKSensitive(english))
}

@Test
func audioLevelMeterAppliesSmoothingAndKeepsBarsVisible() {
    var sourceValues: [Double] = [0.5, 0.5, 0.5, 0.5, 0.5]
    var meter = AudioLevelMeter(randomSource: {
        sourceValues.removeFirst()
    })

    let levels = meter.levels(forRMS: 0.25)
    #expect(levels.count == 5)
    #expect(levels[2] > levels[0])
    #expect(levels.allSatisfy { $0 >= 0.07 })
}

@Test
func textInjectorRestoresClipboardAndInputSource() async throws {
    let clipboard = MockClipboard()
    let inputSource = MockInputSourceManager()
    let injector = TextInjector(clipboard: clipboard, inputSourceManager: inputSource, pastePerformer: {})

    try await injector.inject(text: "你好 world")

    #expect(clipboard.restoredSnapshots == [PasteboardSnapshot(items: [PasteboardSnapshot.Item(dataByType: ["public.utf8-plain-text": Data("before".utf8)])])])
    #expect(inputSource.selectedIDs == ["ascii", "cjk"])
    #expect(clipboard.replacedText == "你好 world")
}

private final class MockClipboard: ClipboardManaging {
    private(set) var replacedText: String = ""
    private(set) var restoredSnapshots: [PasteboardSnapshot] = []

    func snapshot() -> PasteboardSnapshot {
        PasteboardSnapshot(items: [.init(dataByType: ["public.utf8-plain-text": Data("before".utf8)])])
    }

    func replaceContents(with text: String) throws {
        replacedText = text
    }

    func restore(from snapshot: PasteboardSnapshot) {
        restoredSnapshots.append(snapshot)
    }
}

private final class MockInputSourceManager: InputSourceManaging {
    private(set) var selectedIDs: [String] = []

    func currentInputSource() -> InputSourceDescriptor? {
        InputSourceDescriptor(
            id: "cjk",
            languages: ["zh-Hans"],
            sourceType: "TISTypeKeyboardInputMethodModeEnabled",
            isASCII: false
        )
    }

    func asciiCapableInputSource() -> InputSourceDescriptor? {
        InputSourceDescriptor(
            id: "ascii",
            languages: ["en"],
            sourceType: "TISTypeKeyboardLayout",
            isASCII: true
        )
    }

    func selectInputSource(withID id: String) -> Bool {
        selectedIDs.append(id)
        return true
    }
}
