import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: AppSettings

    private let defaults: UserDefaults

    private enum Keys {
        static let language = "selectedLanguage"
        static let llmEnabled = "llmEnabled"
        static let llmBaseURL = "llmBaseURL"
        static let llmAPIKey = "llmAPIKey"
        static let llmModel = "llmModel"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let language = SupportedLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .defaultLanguage
        let llmEnabled = defaults.object(forKey: Keys.llmEnabled) as? Bool ?? false
        let configuration = LLMConfiguration(
            baseURL: defaults.string(forKey: Keys.llmBaseURL) ?? "",
            apiKey: defaults.string(forKey: Keys.llmAPIKey) ?? "",
            model: defaults.string(forKey: Keys.llmModel) ?? ""
        )

        self.settings = AppSettings(
            selectedLanguage: language,
            llmEnabled: llmEnabled,
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

    func save(configuration: LLMConfiguration) {
        settings.llmConfiguration = configuration
        defaults.set(configuration.baseURL, forKey: Keys.llmBaseURL)
        defaults.set(configuration.apiKey, forKey: Keys.llmAPIKey)
        defaults.set(configuration.model, forKey: Keys.llmModel)
    }
}
