import AppKit
import ApplicationServices
import AVFoundation
import Speech
import SwiftUI

@MainActor
final class PermissionsCoordinator: ObservableObject {
    @Published private(set) var snapshot = PermissionsSnapshot(
        microphone: .notDetermined,
        speech: .notDetermined,
        accessibility: .notDetermined,
        inputMonitoring: .notDetermined
    )

    func refresh() {
        let microphoneStatus: PermissionState
        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                microphoneStatus = .authorized
            case .denied:
                microphoneStatus = .denied
            case .undetermined:
                microphoneStatus = .notDetermined
            @unknown default:
                microphoneStatus = .unavailable
            }
        } else {
            microphoneStatus = .unavailable
        }

        let speechStatus: PermissionState
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechStatus = .authorized
        case .denied, .restricted:
            speechStatus = .denied
        case .notDetermined:
            speechStatus = .notDetermined
        @unknown default:
            speechStatus = .unavailable
        }

        let accessibilityStatus: PermissionState = AXIsProcessTrusted() ? .authorized : .denied
        let inputMonitoringStatus: PermissionState = FnKeyMonitor.canCreateProbeTap() ? .authorized : .denied

        snapshot = PermissionsSnapshot(
            microphone: microphoneStatus,
            speech: speechStatus,
            accessibility: accessibilityStatus,
            inputMonitoring: inputMonitoringStatus
        )
    }

    func requestMicrophone() async {
        guard #available(macOS 14.0, *) else {
            refresh()
            return
        }

        _ = await AVAudioApplication.requestRecordPermission()
        refresh()
    }

    func requestSpeech() async {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { _ in
                continuation.resume()
            }
        }
        refresh()
    }

    func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSettings(anchor: "Privacy_Accessibility")
        refresh()
    }

    func openSettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
