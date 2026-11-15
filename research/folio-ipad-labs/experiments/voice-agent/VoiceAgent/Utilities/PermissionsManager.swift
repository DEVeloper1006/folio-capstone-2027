import AppKit
import ApplicationServices
import AVFoundation
import Speech

/// Tracks and requests the three TCC permissions the agent needs.
@MainActor
@Observable
final class PermissionsManager {
    enum Status: String, Sendable {
        case granted, denied, notDetermined

        var isGranted: Bool { self == .granted }
    }

    private(set) var accessibility: Status = .notDetermined
    private(set) var microphone: Status = .notDetermined
    private(set) var speech: Status = .notDetermined

    var allGranted: Bool { accessibility.isGranted && microphone.isGranted && speech.isGranted }

    init() {
        refresh()
    }

    func refresh() {
        accessibility = AXIsProcessTrusted() ? .granted : .denied

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphone = .granted
        case .notDetermined: microphone = .notDetermined
        default: microphone = .denied
        }

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: speech = .granted
        case .notDetermined: speech = .notDetermined
        default: speech = .denied
        }
    }

    /// Shows the system Accessibility prompt. The user must toggle the app in System Settings;
    /// AX trust is not reported back asynchronously, so callers should `refresh()` later.
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        accessibility = AXIsProcessTrustedWithOptions(options) ? .granted : .denied
    }

    func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphone = granted ? .granted : .denied
    }

    func requestSpeech() async {
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        speech = status == .authorized ? .granted : .denied
    }

    /// Requests microphone and speech. Accessibility is deliberately not prompted here: debug rebuilds
    /// invalidate the grant, and re-prompting on every launch just stacks dialogs. The pill shows
    /// "Re-grant Accessibility in System Settings" instead, and Settings has an explicit Grant button.
    func requestAll() async {
        if microphone == .notDetermined { await requestMicrophone() }
        if speech == .notDetermined { await requestSpeech() }
        refresh()
    }

    func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    func openSpeechSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
