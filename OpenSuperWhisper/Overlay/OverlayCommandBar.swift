import AppKit
import SwiftUI

@MainActor
struct OverlayCommandBar: View {
    @ObservedObject var overlayState: MainOverlayViewState
    let onMoveSelection: (Int) -> Void
    let onSubmit: () -> Void
    let onEscape: () -> Void

    var body: some View {
        OverlayInsetSurface(tone: .command, cornerRadius: 26) {
            HStack(spacing: 12) {
                Image(systemName: overlayState.commandMode == .quickActions ? "command.square" : "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(overlayState.commandMode == .quickActions ? .blue : .secondary)
                    .frame(width: 18)

                OverlayCommandTextField(
                    text: Binding(
                        get: { overlayState.commandText },
                        set: { overlayState.commandText = $0 }
                    ),
                    focusTrigger: overlayState.focusTrigger,
                    placeholder: "Search transcripts or type > for actions",
                    onArrowUp: { onMoveSelection(-1) },
                    onArrowDown: { onMoveSelection(1) },
                    onEnter: onSubmit,
                    onEscape: onEscape
                )

                if overlayState.commandMode == .quickActions {
                    Text("Actions")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }

                Text("esc")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 0.8)
                    )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}

@MainActor
private struct OverlayCommandTextField: NSViewRepresentable {
    @Binding var text: String
    let focusTrigger: UUID
    let placeholder: String
    let onArrowUp: () -> Void
    let onArrowDown: () -> Void
    let onEnter: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> OverlayTextField {
        let textField = OverlayTextField()
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 17, weight: .regular)
        textField.placeholderString = placeholder

        DispatchQueue.main.async {
            textField.window?.makeFirstResponder(textField)
        }

        return textField
    }

    func updateNSView(_ nsView: OverlayTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }

        context.coordinator.parent = self

        if context.coordinator.lastFocusTrigger != focusTrigger {
            context.coordinator.lastFocusTrigger = focusTrigger
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: OverlayCommandTextField
        var lastFocusTrigger: UUID

        init(parent: OverlayCommandTextField) {
            self.parent = parent
            self.lastFocusTrigger = parent.focusTrigger
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onArrowUp()
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onArrowDown()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onEnter()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            default:
                return false
            }
        }

        func handleKeyDown(_ event: NSEvent, in textField: NSTextField) -> Bool {
            switch event.keyCode {
            case 126:
                parent.onArrowUp()
                return true
            case 125:
                parent.onArrowDown()
                return true
            case 36:
                parent.onEnter()
                return true
            case 53:
                parent.onEscape()
                return true
            default:
                return false
            }
        }
    }
}

@MainActor
private final class OverlayTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return
        }

        if let coordinator = delegate as? OverlayCommandTextField.Coordinator,
           coordinator.handleKeyDown(event, in: self) {
            return
        }

        super.keyDown(with: event)
    }
}
