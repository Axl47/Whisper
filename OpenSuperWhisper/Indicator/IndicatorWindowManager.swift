import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

@MainActor
class IndicatorWindowManager: IndicatorViewDelegate {
    static let shared = IndicatorWindowManager()
    
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
                contentRect: NSRect(x: 0, y: 0, width: 220, height: 72),
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
        
        // Position window - use the screen containing the point, or main screen as fallback
        let targetScreen = point.flatMap { FocusUtils.screenContaining(point: $0) } ?? NSScreen.main
        if let window = window, let screen = targetScreen {
            let windowFrame = window.frame
            let screenFrame = screen.frame
            
            var x: CGFloat
            var y: CGFloat
            
            if let point = point {
                // Position near cursor
                x = point.x - windowFrame.width / 2
                y = point.y + 20 // 20 points above cursor
            } else {
                // Default to top center of screen
                x = screenFrame.midX - windowFrame.width / 2
                y = screenFrame.maxY - windowFrame.height - 100 // 100 pixels from top
            }
            
            // Adjust if out of screen bounds
            x = max(screenFrame.minX, min(x, screenFrame.maxX - windowFrame.width))
            y = max(screenFrame.minY, min(y, screenFrame.maxY - windowFrame.height))
            
            window.setFrameOrigin(NSPoint(x: x, y: y))
            
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
        let clampedWidth = min(max(fittingSize.width, 220), 420)
        let clampedHeight = min(max(fittingSize.height, 72), targetScreenFrame.height - 120)
        let newOriginX = min(
            max(targetScreenFrame.minX, currentFrame.midX - clampedWidth / 2),
            targetScreenFrame.maxX - clampedWidth
        )
        let newOriginY = min(
            max(targetScreenFrame.minY, currentFrame.maxY - clampedHeight),
            targetScreenFrame.maxY - clampedHeight
        )

        let newFrame = NSRect(
            x: newOriginX,
            y: newOriginY,
            width: clampedWidth,
            height: clampedHeight
        )
        window.setFrame(newFrame, display: true)
    }
}
