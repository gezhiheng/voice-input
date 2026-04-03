import Foundation
import Testing
@testable import VoiceInputApp

@Test
func defaultLanguageIsSimplifiedChinese() {
    #expect(AppSettings.default.selectedLanguage == .simplifiedChinese)
    #expect(AppSettings.default.llmRefinementMode == .conservativeCorrection)
    #expect(AppSettings.default.llmConfiguration.baseURL == LLMConfiguration.bailianBaseURL)
    #expect(AppSettings.default.llmConfiguration.model == LLMConfiguration.bailianModel)
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
        store.updateLLMRefinementMode(.structuredRewrite)
        store.save(configuration: .init(baseURL: "https://example.com/v1", apiKey: "", model: "gpt-test"))

        #expect(store.settings.selectedLanguage == .japanese)
        #expect(store.settings.llmRefinementMode == .structuredRewrite)
        #expect(store.settings.llmConfiguration.apiKey == "")
        #expect(defaults.string(forKey: "llmRefinementMode") == LLMRefinementMode.structuredRewrite.rawValue)
        #expect(defaults.string(forKey: "llmAPIKey") == "")
    }
}

@Test
func llmEndpointNormalizationHandlesBaseAndFullEndpoint() throws {
    let refiner = LLMRefiner(session: URLSession(configuration: .ephemeral))

    let base = try refiner.normalizedEndpoint(from: "https://api.openai.com/v1")
    #expect(base.absoluteString == "https://api.openai.com/v1/chat/completions")

    let bailian = try refiner.normalizedEndpoint(from: LLMConfiguration.bailianBaseURL)
    #expect(bailian.absoluteString == "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")

    let full = try refiner.normalizedEndpoint(from: "https://example.com/custom/chat/completions")
    #expect(full.absoluteString == "https://example.com/custom/chat/completions")

    let root = try refiner.normalizedEndpoint(from: "https://example.com")
    #expect(root.absoluteString == "https://example.com/v1/chat/completions")
}

@Test
func llmRefinerUsesBailianFriendlyPromptAndDisablesThinking() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CorrectionMockURLProtocol.self]

    let requestBox = RequestBox()
    CorrectionMockURLProtocol.requestHandler = { request in
        requestBox.request = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let data = Data(#"{"choices":[{"message":{"content":"Python 和 JSON"}}]}"#.utf8)
        return (response, data)
    }

    defer {
        CorrectionMockURLProtocol.requestHandler = nil
    }

    let refiner = LLMRefiner(session: URLSession(configuration: configuration))
    let refined = try await refiner.refine(
        "配森 和 杰森",
        configuration: LLMConfiguration(
            baseURL: LLMConfiguration.bailianBaseURL,
            apiKey: "test-key",
            model: LLMConfiguration.bailianModel
        ),
        mode: .conservativeCorrection
    )

    #expect(refined == "Python 和 JSON")

    let request = try #require(requestBox.request)
    let body = try #require(requestBody(from: request))
    let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

    #expect(payload["model"] as? String == LLMConfiguration.bailianModel)
    #expect(payload["temperature"] as? Double == 0)
    #expect(payload["seed"] as? Int == 1234)
    #expect(payload["enable_thinking"] as? Bool == false)

    let messages = try #require(payload["messages"] as? [[String: String]])
    #expect(messages.count == 2)
    #expect(messages[0]["role"] == "system")
    #expect(messages[0]["content"]?.contains("只修正明显错误") == true)
    #expect(messages[1]["role"] == "user")
    #expect(messages[1]["content"]?.contains("原始转写") == true)
}

@Test
func llmRefinerUsesStructuredRewritePromptWhenRequested() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StructuredRewriteMockURLProtocol.self]

    let requestBox = RequestBox()
    StructuredRewriteMockURLProtocol.requestHandler = { request in
        requestBox.request = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let data = Data(#"{"choices":[{"message":{"content":"- 第一项\n- 第二项"}}]}"#.utf8)
        return (response, data)
    }

    defer {
        StructuredRewriteMockURLProtocol.requestHandler = nil
    }

    let refiner = LLMRefiner(session: URLSession(configuration: configuration))
    let refined = try await refiner.refine(
        "第一项是把项目排期重新整理一下然后第二项是把风险和阻塞单独拿出来说",
        configuration: LLMConfiguration(
            baseURL: LLMConfiguration.bailianBaseURL,
            apiKey: "test-key",
            model: LLMConfiguration.bailianModel
        ),
        mode: .structuredRewrite
    )

    #expect(refined == "- 第一项\n- 第二项")

    let request = try #require(requestBox.request)
    let body = try #require(requestBody(from: request))
    let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let messages = try #require(payload["messages"] as? [[String: String]])

    #expect(messages[0]["content"]?.contains("口述内容整理助手") == true)
    #expect(messages[1]["content"]?.contains("总结、提炼并优化表达") == true)
}

@Test
func transcriptAccumulatorKeepsLatinSegmentsSeparated() {
    var accumulator = TranscriptAccumulator()
    accumulator.updateActiveText("hello")
    accumulator.commitActiveText()
    accumulator.updateActiveText("world")

    #expect(accumulator.combinedText == "hello world")
}

@Test
func transcriptAccumulatorKeepsChineseSegmentsContinuous() {
    var accumulator = TranscriptAccumulator()
    accumulator.updateActiveText("你好")
    accumulator.commitActiveText()
    accumulator.updateActiveText("世界")

    #expect(accumulator.combinedText == "你好世界")
}

@Test
func transcriptAccumulatorAvoidsExtraSpaceAroundPunctuation() {
    var accumulator = TranscriptAccumulator()
    accumulator.updateActiveText("hello")
    accumulator.commitActiveText()
    accumulator.updateActiveText(", world")

    #expect(accumulator.combinedText == "hello, world")
}

@Test
func transcriptAccumulatorKeepsEarlierSpeechWhenPartialResetsAfterPause() {
    var accumulator = TranscriptAccumulator()
    accumulator.updateActiveText("我要讲一下项目计划")
    accumulator.updateActiveText("项目计划第一点是本周先完成接口联调")

    #expect(accumulator.combinedText == "我要讲一下项目计划第一点是本周先完成接口联调")
}

@Test
func transcriptAccumulatorTreatsStrongPrefixMatchAsRevisionInsteadOfNewSegment() {
    var accumulator = TranscriptAccumulator()
    accumulator.updateActiveText("我们明天上午开会")
    accumulator.updateActiveText("我们明天下午开会")

    #expect(accumulator.combinedText == "我们明天下午开会")
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
func floatingPanelViewModelKeepsShortTextVisible() async {
    await MainActor.run {
        let viewModel = FloatingPanelViewModel()
        let text = "短句测试"

        viewModel.updateText(text)

        #expect(viewModel.displayedText == text)
    }
}

@Test
func floatingPanelViewModelUsesLeadingEllipsisForLongText() async {
    await MainActor.run {
        let viewModel = FloatingPanelViewModel()
        let text = String(repeating: "前文内容，", count: 20) + "最后这句必须可见"

        viewModel.updateText(text)

        #expect(viewModel.displayedText.first == "…")
        #expect(viewModel.displayedText.contains("最后这句必须可见"))
        #expect(viewModel.displayedText.count < text.count)
    }
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

@Test
func textInjectorRunsClipboardAndInputSourceWorkOnMainThread() async throws {
    let clipboard = ThreadRecordingClipboard()
    let inputSource = ThreadRecordingInputSourceManager()
    let injector = TextInjector(clipboard: clipboard, inputSourceManager: inputSource, pastePerformer: {})

    try await injector.inject(text: "hello")

    #expect(clipboard.snapshotWasOnMainThread)
    #expect(clipboard.replaceWasOnMainThread)
    #expect(clipboard.restoreWasOnMainThread)
    #expect(inputSource.currentWasOnMainThread)
    #expect(inputSource.asciiWasOnMainThread)
    #expect(inputSource.selectCallThreads == [true, true])
}

@Test
func textInjectorMarshalsClipboardAndInputSourceWorkToMainThreadFromDetachedTask() async throws {
    let clipboard = ThreadRecordingClipboard()
    let inputSource = ThreadRecordingInputSourceManager()
    let injector = TextInjector(clipboard: clipboard, inputSourceManager: inputSource, pastePerformer: {})

    try await Task.detached {
        try await injector.inject(text: "hello")
    }.value

    #expect(clipboard.snapshotWasOnMainThread)
    #expect(clipboard.replaceWasOnMainThread)
    #expect(clipboard.restoreWasOnMainThread)
    #expect(inputSource.currentWasOnMainThread)
    #expect(inputSource.asciiWasOnMainThread)
    #expect(inputSource.selectCallThreads == [true, true])
}

private final class MockClipboard: ClipboardManaging {
    private(set) var replacedText: String = ""
    private(set) var restoredSnapshots: [PasteboardSnapshot] = []

    @MainActor
    func snapshot() -> PasteboardSnapshot {
        PasteboardSnapshot(items: [.init(dataByType: ["public.utf8-plain-text": Data("before".utf8)])])
    }

    @MainActor
    func replaceContents(with text: String) throws {
        replacedText = text
    }

    @MainActor
    func restore(from snapshot: PasteboardSnapshot) {
        restoredSnapshots.append(snapshot)
    }
}

private final class MockInputSourceManager: InputSourceManaging {
    private(set) var selectedIDs: [String] = []

    @MainActor
    func currentInputSource() -> InputSourceDescriptor? {
        InputSourceDescriptor(
            id: "cjk",
            languages: ["zh-Hans"],
            sourceType: "TISTypeKeyboardInputMethodModeEnabled",
            isASCII: false
        )
    }

    @MainActor
    func asciiCapableInputSource() -> InputSourceDescriptor? {
        InputSourceDescriptor(
            id: "ascii",
            languages: ["en"],
            sourceType: "TISTypeKeyboardLayout",
            isASCII: true
        )
    }

    @MainActor
    func selectInputSource(withID id: String) -> Bool {
        selectedIDs.append(id)
        return true
    }
}

private final class ThreadRecordingClipboard: ClipboardManaging {
    private(set) var snapshotWasOnMainThread = false
    private(set) var replaceWasOnMainThread = false
    private(set) var restoreWasOnMainThread = false

    @MainActor
    func snapshot() -> PasteboardSnapshot {
        snapshotWasOnMainThread = Thread.isMainThread
        return PasteboardSnapshot(items: [])
    }

    @MainActor
    func replaceContents(with text: String) throws {
        replaceWasOnMainThread = Thread.isMainThread
    }

    @MainActor
    func restore(from snapshot: PasteboardSnapshot) {
        restoreWasOnMainThread = Thread.isMainThread
    }
}

private final class ThreadRecordingInputSourceManager: InputSourceManaging {
    private(set) var currentWasOnMainThread = false
    private(set) var asciiWasOnMainThread = false
    private(set) var selectCallThreads: [Bool] = []

    @MainActor
    func currentInputSource() -> InputSourceDescriptor? {
        currentWasOnMainThread = Thread.isMainThread
        return InputSourceDescriptor(
            id: "cjk",
            languages: ["zh-Hans"],
            sourceType: "TISTypeKeyboardInputMethodModeEnabled",
            isASCII: false
        )
    }

    @MainActor
    func asciiCapableInputSource() -> InputSourceDescriptor? {
        asciiWasOnMainThread = Thread.isMainThread
        return InputSourceDescriptor(
            id: "ascii",
            languages: ["en"],
            sourceType: "TISTypeKeyboardLayout",
            isASCII: true
        )
    }

    @MainActor
    func selectInputSource(withID id: String) -> Bool {
        selectCallThreads.append(Thread.isMainThread)
        return true
    }
}

private final class RequestBox: @unchecked Sendable {
    var request: URLRequest?
}

private final class CorrectionMockURLProtocol: URLProtocol, @unchecked Sendable {
    static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            fatalError("MockURLProtocol.requestHandler must be set before use.")
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class StructuredRewriteMockURLProtocol: URLProtocol, @unchecked Sendable {
    static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            fatalError("StructuredRewriteMockURLProtocol.requestHandler must be set before use.")
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func requestBody(from request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer {
        stream.close()
    }

    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer {
        buffer.deallocate()
    }

    var data = Data()
    while stream.hasBytesAvailable {
        let readCount = stream.read(buffer, maxLength: bufferSize)
        if readCount < 0 {
            return nil
        }

        if readCount == 0 {
            break
        }

        data.append(buffer, count: readCount)
    }

    return data
}
