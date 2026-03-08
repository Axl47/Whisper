import Foundation

enum OverlayCommandMode {
    case search
    case quickActions
}

struct OverlayQuickAction: Identifiable {
    let id: String
    let symbolName: String
    let title: String
    let subtitle: String
    let isDestructive: Bool
    let perform: () -> Void
}

@MainActor
final class MainOverlayViewState: ObservableObject {
    @Published var commandText = ""
    @Published var selectedIndex = 0
    @Published var focusTrigger = UUID()
    @Published var suppressResignDismissal = false

    var commandMode: OverlayCommandMode {
        commandText.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(">")
            ? .quickActions
            : .search
    }

    var quickActionQuery: String {
        let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(">") else { return "" }
        return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func prepareForPresentation() {
        selectedIndex = 0
        focusTrigger = UUID()
    }

    func resetForDismissal() {
        commandText = ""
        selectedIndex = 0
        suppressResignDismissal = false
        focusTrigger = UUID()
    }

    func moveSelection(by delta: Int, totalCount: Int) {
        guard totalCount > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = max(0, min(selectedIndex + delta, totalCount - 1))
    }

    func clampSelection(totalCount: Int) {
        guard totalCount > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(selectedIndex, totalCount - 1)
    }
}
