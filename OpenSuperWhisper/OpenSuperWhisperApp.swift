import SwiftUI

@main
struct OpenSuperWhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        SwiftUI.Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }

    init() {
        _ = AppState.shared
        _ = ShortcutManager.shared
        _ = MicrophoneService.shared
        WhisperModelManager.shared.ensureDefaultModelPresent()
    }
}

extension OpenSuperWhisperApp {
    static func startTranscriptionQueue() {
        Task { @MainActor in
            TranscriptionQueue.shared.startProcessingQueue()
        }
    }
}
