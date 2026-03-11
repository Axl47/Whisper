import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

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
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
    }

    private func createWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("SettingsWindow")
        window.contentView = NSHostingView(
            rootView: SettingsView(
                onDone: { [weak self] in
                    self?.close()
                }
            )
        )

        self.window = window
    }
}
