import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

@MainActor
class IndicatorWindowManager: IndicatorViewDelegate {
    static let shared = IndicatorWindowManager()
    private static let minimumPanelWidth: CGFloat = 220
    private static let maximumPanelWidth: CGFloat = 420
    private static let minimumPanelHeight: CGFloat = 72
    private static let screenEdgeInset: CGFloat = 24
    private static let bottomOffset: CGFloat = 96
    
    var window: NSWindow?
    var viewModel: IndicatorViewModel?
    private var hostingView: NSHostingView<IndicatorWindow>?
    private var sizeObservationCancellables = Set<AnyCancellable>()
    
    private init() {}
    
    func show(nearPoint point: NSPoint? = nil) -> IndicatorViewModel {
        
        KeyboardShortcuts.enable(.escape)
        
        // Create new view model
        let newViewModel = IndicatorViewModel()
        newViewModel.delegate = self
        viewModel = newViewModel
        
        if window == nil {
            // Create window if it doesn't exist - using NSPanel for full-screen compatibility
            let panel = NSPanel(
                contentRect: NSRect(
                    x: 0,
                    y: 0,
                    width: Self.minimumPanelWidth,
                    height: Self.minimumPanelHeight
                ),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            
            panel.isFloatingPanel = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            
            self.window = panel
        }
        
        // Use the point only to choose the target screen. The indicator itself stays pinned
        // to a lower-center position on that screen instead of following the caret/cursor.
        let targetScreen = point.flatMap { FocusUtils.screenContaining(point: $0) } ?? NSScreen.main
        if let window = window, let screen = targetScreen {
            let initialFrame = preferredFrame(
                in: screen.visibleFrame,
                size: CGSize(width: Self.minimumPanelWidth, height: Self.minimumPanelHeight)
            )
            window.setFrame(initialFrame, display: true)
            
            // Set content view
            let hostingView = NSHostingView(rootView: IndicatorWindow(viewModel: newViewModel))
            self.hostingView = hostingView
            window.contentView = hostingView

            bindWindowSize(to: newViewModel)
            resizeWindowToFitContent()
        }
        
        window?.orderFront(nil)
        return newViewModel
    }
    
    func stopRecording() {
        viewModel?.startDecoding()
    }
    
    func stopForce() {
        viewModel?.cancelRecording()
        viewModel?.cleanup()
        hide()
    }

    func hide() {
        KeyboardShortcuts.disable(.escape)
        
        Task {
            guard let viewModel = self.viewModel else { return }
            
            await viewModel.hideWithAnimation()
            viewModel.cleanup()
            
            self.window?.contentView = nil
            self.window?.orderOut(nil)
            self.hostingView = nil
            self.viewModel = nil
            self.sizeObservationCancellables.removeAll()
            
            NotificationCenter.default.post(name: .indicatorWindowDidHide, object: nil)
        }
    }
    
    func didFinishDecoding() {
        hide()
    }

    private func bindWindowSize(to viewModel: IndicatorViewModel) {
        sizeObservationCancellables.removeAll()

        viewModel.$state
            .combineLatest(viewModel.$liveCommittedText, viewModel.$livePreviewText)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.resizeWindowToFitContent()
            }
            .store(in: &sizeObservationCancellables)
    }

    private func resizeWindowToFitContent() {
        guard let window, let hostingView else {
            return
        }

        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        guard fittingSize.width > 0, fittingSize.height > 0 else {
            return
        }

        let currentFrame = window.frame
        let targetScreenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? currentFrame
        let clampedWidth = min(max(fittingSize.width, Self.minimumPanelWidth), Self.maximumPanelWidth)
        let clampedHeight = min(
            max(fittingSize.height, Self.minimumPanelHeight),
            targetScreenFrame.height - (Self.screenEdgeInset * 2)
        )
        let newFrame = preferredFrame(
            in: targetScreenFrame,
            size: CGSize(width: clampedWidth, height: clampedHeight)
        )
        window.setFrame(newFrame, display: true)
    }

    private func preferredFrame(in visibleFrame: NSRect, size: CGSize) -> NSRect {
        let originX = visibleFrame.midX - size.width / 2
        let originY = visibleFrame.minY + Self.bottomOffset

        let clampedOriginX = min(
            max(visibleFrame.minX + Self.screenEdgeInset, originX),
            visibleFrame.maxX - size.width - Self.screenEdgeInset
        )
        let clampedOriginY = min(
            max(visibleFrame.minY + Self.screenEdgeInset, originY),
            visibleFrame.maxY - size.height - Self.screenEdgeInset
        )

        return NSRect(
            x: clampedOriginX,
            y: clampedOriginY,
            width: size.width,
            height: size.height
        )
    }
}
