import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: AppSettings

    private let defaults: UserDefaults

    private enum Keys {
        static let language = "selectedLanguage"
        static let llmEnabled = "llmEnabled"
        static let llmRefinementMode = "llmRefinementMode"
        static let llmBaseURL = "llmBaseURL"
        static let llmAPIKey = "llmAPIKey"
        static let llmModel = "llmModel"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let language = SupportedLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .defaultLanguage
        let llmEnabled = defaults.object(forKey: Keys.llmEnabled) as? Bool ?? false
        let llmRefinementMode = LLMRefinementMode(
            rawValue: defaults.string(forKey: Keys.llmRefinementMode) ?? ""
        ) ?? .conservativeCorrection
        let configuration = LLMConfiguration(
            baseURL: defaults.string(forKey: Keys.llmBaseURL) ?? LLMConfiguration.bailianBaseURL,
            apiKey: defaults.string(forKey: Keys.llmAPIKey) ?? "",
            model: defaults.string(forKey: Keys.llmModel) ?? LLMConfiguration.bailianModel
        )

        self.settings = AppSettings(
            selectedLanguage: language,
            llmEnabled: llmEnabled,
            llmRefinementMode: llmRefinementMode,
            llmConfiguration: configuration
        )
    }

    func updateLanguage(_ language: SupportedLanguage) {
        settings.selectedLanguage = language
        defaults.set(language.rawValue, forKey: Keys.language)
    }

    func updateLLMEnabled(_ isEnabled: Bool) {
        settings.llmEnabled = isEnabled
        defaults.set(isEnabled, forKey: Keys.llmEnabled)
    }

    func updateLLMRefinementMode(_ mode: LLMRefinementMode) {
        settings.llmRefinementMode = mode
        defaults.set(mode.rawValue, forKey: Keys.llmRefinementMode)
    }

    func save(configuration: LLMConfiguration) {
        settings.llmConfiguration = configuration
        defaults.set(configuration.baseURL, forKey: Keys.llmBaseURL)
        defaults.set(configuration.apiKey, forKey: Keys.llmAPIKey)
        defaults.set(configuration.model, forKey: Keys.llmModel)
    }
}
