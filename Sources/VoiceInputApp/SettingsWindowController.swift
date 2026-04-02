import AppKit
import SwiftUI

@MainActor
final class SettingsWindowViewModel: ObservableObject {
    @Published var baseURL: String
    @Published var apiKey: String
    @Published var model: String
    @Published var statusMessage: String = ""
    @Published var isTesting = false

    private let settingsStore: SettingsStore
    private let textRefiner: TextRefining

    init(settingsStore: SettingsStore, textRefiner: TextRefining) {
        self.settingsStore = settingsStore
        self.textRefiner = textRefiner
        self.baseURL = settingsStore.settings.llmConfiguration.baseURL
        self.apiKey = settingsStore.settings.llmConfiguration.apiKey
        self.model = settingsStore.settings.llmConfiguration.model
    }

    func reload() {
        let configuration = settingsStore.settings.llmConfiguration
        baseURL = configuration.baseURL
        apiKey = configuration.apiKey
        model = configuration.model
        statusMessage = ""
    }

    func save() {
        settingsStore.save(
            configuration: LLMConfiguration(
                baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                apiKey: apiKey,
                model: model.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
        statusMessage = "Saved."
    }

    func test() {
        let configuration = LLMConfiguration(
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey,
            model: model.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        isTesting = true
        statusMessage = "Testing…"

        Task {
            defer {
                Task { @MainActor in
                    self.isTesting = false
                }
            }

            do {
                try await textRefiner.testConnection(configuration: configuration)
                await MainActor.run {
                    self.statusMessage = "Connection successful."
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private let viewModel: SettingsWindowViewModel

    init(viewModel: SettingsWindowViewModel) {
        self.viewModel = viewModel

        let rootView = SettingsRootView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 280),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LLM Refinement Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = hostingView

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        viewModel.reload()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SettingsRootView: View {
    @ObservedObject var viewModel: SettingsWindowViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configure the OpenAI-compatible endpoint used for conservative transcript correction.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("API Base URL")
                        .frame(width: 96, alignment: .leading)
                    TextField("https://api.openai.com/v1", text: $viewModel.baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("API Key")
                        .frame(width: 96, alignment: .leading)
                    SecureField("sk-...", text: $viewModel.apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Model")
                        .frame(width: 96, alignment: .leading)
                    TextField("gpt-4.1-mini", text: $viewModel.model)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Text(viewModel.statusMessage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()

                Button("Test") {
                    viewModel.test()
                }
                .disabled(viewModel.isTesting)

                Button("Save") {
                    viewModel.save()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
