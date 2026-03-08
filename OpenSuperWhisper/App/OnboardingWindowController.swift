import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private let appState: AppState
    private var window: NSWindow?

    init(appState: AppState) {
        self.appState = appState
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func show() {
        if window == nil {
            createWindow()
        }

        guard let window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
    }

    private func createWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 680),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("OnboardingWindow")
        window.contentView = NSHostingView(rootView: OnboardingView().environmentObject(appState))

        self.window = window
    }
}
