import AppKit
import Combine
import SwiftUI

@MainActor
final class PermissionsWindowController: NSWindowController {
    private let coordinator: PermissionsCoordinator

    init(coordinator: PermissionsCoordinator) {
        self.coordinator = coordinator

        let rootView = PermissionsRootView(coordinator: coordinator)
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Permissions"
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
        coordinator.refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct PermissionsRootView: View {
    @ObservedObject var coordinator: PermissionsCoordinator
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("VoiceInput needs microphone, speech recognition, accessibility, and input monitoring access to record globally and paste reliably.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            permissionRow(
                title: "Microphone",
                state: coordinator.snapshot.microphone,
                buttonTitle: "Request"
            ) {
                Task {
                    await coordinator.requestMicrophone()
                }
            }

            permissionRow(
                title: "Speech Recognition",
                state: coordinator.snapshot.speech,
                buttonTitle: "Request"
            ) {
                Task {
                    await coordinator.requestSpeech()
                }
            }

            permissionRow(
                title: "Accessibility",
                state: coordinator.snapshot.accessibility,
                buttonTitle: "Open Settings"
            ) {
                coordinator.promptAccessibility()
            }

            permissionRow(
                title: "Input Monitoring",
                state: coordinator.snapshot.inputMonitoring,
                buttonTitle: "Open Settings"
            ) {
                coordinator.openSettings(anchor: "Privacy_ListenEvent")
            }

            HStack {
                Button("Refresh") {
                    coordinator.refresh()
                }

                Spacer()

                Text("Input Monitoring changes may require reopening the app.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            coordinator.refresh()
            setupTimer()
        }
        .onDisappear {
            cancellables.removeAll()
        }
    }

    private func setupTimer() {
        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak coordinator] _ in
                coordinator?.refresh()
            }
            .store(in: &cancellables)
    }

    private func permissionRow(
        title: String,
        state: PermissionState,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(state.title)
                    .font(.system(size: 12))
                    .foregroundStyle(state == .authorized ? .green : .secondary)
            }

            Spacer()

            Button(buttonTitle, action: action)
        }
    }
}
