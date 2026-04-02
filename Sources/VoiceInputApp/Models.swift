import Foundation

enum SupportedLanguage: String, CaseIterable, Codable {
    case english = "en-US"
    case simplifiedChinese = "zh-CN"
    case traditionalChinese = "zh-TW"
    case japanese = "ja-JP"
    case korean = "ko-KR"

    static let defaultLanguage: SupportedLanguage = .simplifiedChinese

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var menuTitle: String {
        switch self {
        case .english:
            "English (en-US)"
        case .simplifiedChinese:
            "简体中文 (zh-CN)"
        case .traditionalChinese:
            "繁體中文 (zh-TW)"
        case .japanese:
            "日本語 (ja-JP)"
        case .korean:
            "한국어 (ko-KR)"
        }
    }
}

struct LLMConfiguration: Equatable, Codable {
    var baseURL: String
    var apiKey: String
    var model: String

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct AppSettings: Equatable, Codable {
    var selectedLanguage: SupportedLanguage
    var llmEnabled: Bool
    var llmConfiguration: LLMConfiguration

    static let `default` = AppSettings(
        selectedLanguage: .defaultLanguage,
        llmEnabled: false,
        llmConfiguration: LLMConfiguration(baseURL: "", apiKey: "", model: "")
    )
}

enum RecordingPhase: Equatable {
    case idle
    case listening
    case refining
    case injecting
    case error(String)
}

struct InputSourceDescriptor: Equatable {
    var id: String
    var languages: [String]
    var sourceType: String
    var isASCII: Bool
}

enum PermissionState: String {
    case authorized
    case denied
    case notDetermined
    case unavailable

    var title: String {
        switch self {
        case .authorized:
            "Granted"
        case .denied:
            "Required"
        case .notDetermined:
            "Pending"
        case .unavailable:
            "Unknown"
        }
    }
}

struct PermissionsSnapshot: Equatable {
    var microphone: PermissionState
    var speech: PermissionState
    var accessibility: PermissionState
    var inputMonitoring: PermissionState

    var allRequiredGranted: Bool {
        microphone == .authorized &&
        speech == .authorized &&
        accessibility == .authorized &&
        inputMonitoring == .authorized
    }
}

protocol SpeechTranscribing: AnyObject {
    func start(
        locale: Locale,
        partialHandler: @escaping (String) -> Void,
        levelHandler: @escaping ([Double]) -> Void
    ) async throws
    func stop() async throws -> String
    func cancel()
}

protocol TextRefining {
    func refine(_ text: String, configuration: LLMConfiguration) async throws -> String
    func testConnection(configuration: LLMConfiguration) async throws
}

protocol ClipboardManaging {
    func snapshot() -> PasteboardSnapshot
    func replaceContents(with text: String) throws
    func restore(from snapshot: PasteboardSnapshot)
}

protocol InputSourceManaging {
    func currentInputSource() -> InputSourceDescriptor?
    func asciiCapableInputSource() -> InputSourceDescriptor?
    func selectInputSource(withID id: String) -> Bool
}

enum VoiceInputError: LocalizedError {
    case missingPermissions
    case speechRecognizerUnavailable
    case microphoneUnavailable
    case pasteSimulationFailed
    case invalidLLMEndpoint
    case llmResponseMissingContent
    case message(String)

    var errorDescription: String? {
        switch self {
        case .missingPermissions:
            "Required permissions are missing."
        case .speechRecognizerUnavailable:
            "Speech recognition is unavailable for the selected language."
        case .microphoneUnavailable:
            "The microphone is unavailable."
        case .pasteSimulationFailed:
            "Paste simulation failed."
        case .invalidLLMEndpoint:
            "The API base URL is invalid."
        case .llmResponseMissingContent:
            "The LLM response did not contain any text."
        case .message(let message):
            message
        }
    }
}
