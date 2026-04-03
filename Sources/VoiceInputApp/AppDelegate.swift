import AppKit
import Combine
import QuartzCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let settingsStore = SettingsStore()
    private let permissionsCoordinator = PermissionsCoordinator()
    private let speechRecognizer = SpeechRecognizerService()
    private let panelController = FloatingPanelController()
    private let inputSourceManager = InputSourceManager()
    private lazy var clipboardManager = PasteboardClipboardManager()
    private lazy var textInjector = TextInjector(
        clipboard: clipboardManager,
        inputSourceManager: inputSourceManager
    )
    private let textRefiner = LLMRefiner()
    private let fnKeyMonitor = FnKeyMonitor()

    private lazy var settingsWindowController = SettingsWindowController(
        viewModel: SettingsWindowViewModel(
            settingsStore: settingsStore,
            textRefiner: textRefiner
        )
    )
    private lazy var permissionsWindowController = PermissionsWindowController(
        coordinator: permissionsCoordinator
    )
    private lazy var recordingCoordinator = RecordingCoordinator(
        settingsStore: settingsStore,
        permissionsCoordinator: permissionsCoordinator,
        speechRecognizer: speechRecognizer,
        panelController: panelController,
        textInjector: textInjector,
        textRefiner: textRefiner,
        showPermissionsWindow: { [weak self] in
            self?.permissionsWindowController.present()
        }
    )

    private let menu = NSMenu()
    private var cancellables: Set<AnyCancellable> = []
    private var currentStatusSymbolName: String?

    private var canUseStructuredRewrite: Bool {
        let settings = settingsStore.settings
        return settings.llmEnabled && settings.llmConfiguration.isConfigured
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        configureStatusItem()
        configureEventMonitor()
        permissionsCoordinator.refresh()

        settingsStore.$settings
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        recordingCoordinator.$phase
            .sink { [weak self] phase in
                self?.updateStatusItemIcon(for: phase)
            }
            .store(in: &cancellables)

        rebuildMenu()
        updateStatusItemIcon(for: recordingCoordinator.phase)

        if !permissionsCoordinator.snapshot.allRequiredGranted {
            permissionsWindowController.present()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        fnKeyMonitor.stop()
        recordingCoordinator.cancel()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.wantsLayer = true
            button.imagePosition = .imageOnly
        }

        menu.delegate = self
        statusItem.menu = menu
    }

    private func configureEventMonitor() {
        fnKeyMonitor.onPress = { [weak self] in
            self?.recordingCoordinator.handleFnPressed()
        }

        fnKeyMonitor.onRelease = { [weak self] in
            self?.recordingCoordinator.handleFnReleased()
        }

        fnKeyMonitor.start()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let languageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        for language in SupportedLanguage.allCases {
            let item = NSMenuItem(
                title: language.menuTitle,
                action: #selector(selectLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = language.rawValue
            item.state = settingsStore.settings.selectedLanguage == language ? .on : .off
            languageMenu.addItem(item)
        }
        menu.setSubmenu(languageMenu, for: languageItem)
        menu.addItem(languageItem)

        let llmItem = NSMenuItem(title: "LLM Refinement", action: nil, keyEquivalent: "")
        let llmMenu = NSMenu()

        let toggleItem = NSMenuItem(
            title: "Enabled",
            action: #selector(toggleLLMEnabled(_:)),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.state = settingsStore.settings.llmEnabled ? .on : .off
        llmMenu.addItem(toggleItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openLLMSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        llmMenu.addItem(settingsItem)

        menu.setSubmenu(llmMenu, for: llmItem)
        menu.addItem(llmItem)

        let structuredRewriteItem = NSMenuItem(
            title: "Structured Rewrite",
            action: #selector(toggleStructuredRewrite(_:)),
            keyEquivalent: "s"
        )
        structuredRewriteItem.target = self
        structuredRewriteItem.keyEquivalentModifierMask = [.command]
        structuredRewriteItem.isEnabled = canUseStructuredRewrite
        structuredRewriteItem.state = canUseStructuredRewrite && settingsStore.settings.llmRefinementMode == .structuredRewrite ? .on : .off
        menu.addItem(structuredRewriteItem)

        let permissionsItem = NSMenuItem(
            title: "Permissions…",
            action: #selector(openPermissions(_:)),
            keyEquivalent: ""
        )
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func updateStatusItemIcon(for phase: RecordingPhase) {
        guard let button = statusItem.button else {
            return
        }

        let symbolName: String
        let description: String

        switch phase {
        case .listening:
            symbolName = "record.circle.fill"
            description = "Voice Input Recording"
        case .refining, .injecting:
            symbolName = "ellipsis.circle.fill"
            description = "Voice Input Processing"
        case .error:
            symbolName = "exclamationmark.triangle.fill"
            description = "Voice Input Error"
        case .idle:
            symbolName = "mic.fill"
            description = "Voice Input Idle"
        }

        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: description
        ).flatMap { sourceImage in
            makeStatusBarImage(from: sourceImage)
        }

        if currentStatusSymbolName != symbolName {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.18
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            button.layer?.add(transition, forKey: "voiceInputStatusIconFade")
            currentStatusSymbolName = symbolName
        }

        button.image = image
        button.toolTip = description
    }

    private func makeStatusBarImage(from sourceImage: NSImage) -> NSImage? {
        let configured = sourceImage.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        ) ?? sourceImage

        let canvasSize = NSSize(width: 18, height: 18)
        let image = NSImage(size: canvasSize)
        image.lockFocus()

        let targetRect = NSRect(origin: .zero, size: canvasSize).insetBy(dx: 0.75, dy: 0.75)
        let drawSize = configured.size.equalTo(.zero) ? targetRect.size : configured.size
        let scale = min(targetRect.width / drawSize.width, targetRect.height / drawSize.height)
        let finalSize = NSSize(width: drawSize.width * scale, height: drawSize.height * scale)
        let finalRect = NSRect(
            x: (canvasSize.width - finalSize.width) / 2,
            y: (canvasSize.height - finalSize.height) / 2,
            width: finalSize.width,
            height: finalSize.height
        )

        configured.draw(in: finalRect)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    @objc
    private func selectLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = SupportedLanguage(rawValue: rawValue) else {
            return
        }

        settingsStore.updateLanguage(language)
    }

    @objc
    private func toggleLLMEnabled(_ sender: NSMenuItem) {
        settingsStore.updateLLMEnabled(!settingsStore.settings.llmEnabled)
    }

    @objc
    private func toggleStructuredRewrite(_ sender: NSMenuItem) {
        guard canUseStructuredRewrite else {
            return
        }

        let isEnablingStructuredRewrite = settingsStore.settings.llmRefinementMode != .structuredRewrite
        settingsStore.updateLLMRefinementMode(
            isEnablingStructuredRewrite ? .structuredRewrite : .conservativeCorrection
        )
    }

    @objc
    private func openLLMSettings(_ sender: Any?) {
        settingsWindowController.present()
    }

    @objc
    private func openPermissions(_ sender: Any?) {
        permissionsWindowController.present()
    }

    @objc
    private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
