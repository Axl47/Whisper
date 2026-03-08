import Foundation

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var hasCompletedOnboarding: Bool {
        didSet {
            AppPreferences.shared.hasCompletedOnboarding = hasCompletedOnboarding
        }
    }

    private init() {
        var onboarding = AppPreferences.shared.hasCompletedOnboarding
        #if DEBUG
        if let force = DevConfig.shared.forceShowOnboarding {
            onboarding = !force
        }
        #endif
        self.hasCompletedOnboarding = onboarding
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        NotificationCenter.default.post(name: .appStateOnboardingDidComplete, object: nil)
    }
}
