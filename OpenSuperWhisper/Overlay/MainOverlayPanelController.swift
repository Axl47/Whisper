import AppKit
import SwiftUI

@MainActor
final class MainOverlayPanelController {
    private var panel: MainOverlayPanel?

    private let onOpenSettings: () -> Void
    private let onOpenOnboarding: () -> Void

    let viewModel = ContentViewModel()
    let permissionsManager = PermissionsManager()
    let overlayState = MainOverlayViewState()

    init(
        onOpenSettings: @escaping () -> Void,
        onOpenOnboarding: @escaping () -> Void
    ) {
        self.onOpenSettings = onOpenSettings
        self.onOpenOnboarding = onOpenOnboarding
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func toggle() {
        isVisible ? dismiss() : show()
    }

    func show() {
        if panel == nil {
            createPanel()
        }

        guard let panel else { return }

        panel.setFrame(resolvedPanelFrame(), display: true)
        viewModel.loadInitialData()
        overlayState.prepareForPresentation()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss(force: Bool = false) {
        guard force || canDismiss else {
            guard let panel else { return }
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            overlayState.focusTrigger = UUID()
            return
        }

        panel?.orderOut(nil)
        overlayState.resetForDismissal()
    }

    private var canDismiss: Bool {
        guard !overlayState.suppressResignDismissal else { return false }
        return !(viewModel.isRecording || viewModel.state == .decoding || viewModel.state == .connecting)
    }

    private func resolvedPanelFrame() -> NSRect {
        let width: CGFloat = 840
        let height: CGFloat = 660

        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            return NSRect(x: 120, y: 220, width: width, height: height)
        }

        let frame = screen.visibleFrame
        let x = frame.midX - (width / 2)
        let y = frame.maxY - height - 110
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func createPanel() {
        let panel = MainOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 660),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .utilityWindow

        panel.resignHandler = { [weak self] in
            self?.dismiss()
        }

        panel.contentView = NSHostingView(
            rootView: MainOverlayView(
                viewModel: viewModel,
                permissionsManager: permissionsManager,
                overlayState: overlayState,
                onClose: { [weak self] in
                    self?.dismiss()
                },
                onOpenSettings: onOpenSettings,
                onOpenOnboarding: onOpenOnboarding
            )
        )

        self.panel = panel
    }
}
