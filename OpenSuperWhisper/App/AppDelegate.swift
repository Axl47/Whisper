import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState.shared
    private let microphoneService = MicrophoneService.shared

    private var statusItem: NSStatusItem?
    private var languageSubmenu: NSMenu?
    private var microphoneObserver: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    private lazy var overlayController = MainOverlayPanelController(
        onOpenSettings: { [weak self] in
            self?.openSettingsWindow()
        },
        onOpenOnboarding: { [weak self] in
            self?.showOnboardingWindow()
        }
    )

    private lazy var onboardingWindowController = OnboardingWindowController(appState: appState)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarItem()
        observeMicrophoneChanges()
        observeAppState()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languagePreferenceChanged),
            name: .appPreferencesLanguageChanged,
            object: nil
        )

        OpenSuperWhisperApp.startTranscriptionQueue()

        if appState.hasCompletedOnboarding {
            NSApplication.shared.setActivationPolicy(.accessory)
        } else {
            showOnboardingWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        guard isAudioFile(url) else {
            return false
        }

        queueAudioURLs([url])
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let audioURLs = filenames
            .map { URL(fileURLWithPath: $0) }
            .filter { isAudioFile($0) }

        sender.reply(toOpenOrPrint: audioURLs.isEmpty ? .failure : .success)
        queueAudioURLs(audioURLs)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        queueAudioURLs(urls.filter { isAudioFile($0) })
    }

    func showOverlay() {
        guard appState.hasCompletedOnboarding else {
            showOnboardingWindow()
            return
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        overlayController.show()
    }

    func toggleOverlay() {
        guard appState.hasCompletedOnboarding else {
            showOnboardingWindow()
            return
        }
        overlayController.toggle()
    }

    func hideOverlay() {
        overlayController.dismiss(force: true)
    }

    func showOnboardingWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        onboardingWindowController.show()
    }

    private func observeAppState() {
        NotificationCenter.default.publisher(for: .appStateOnboardingDidComplete)
            .sink { [weak self] _ in
                self?.handleOnboardingCompleted()
            }
            .store(in: &cancellables)
    }

    private func handleOnboardingCompleted() {
        onboardingWindowController.close()
        NSApplication.shared.setActivationPolicy(.accessory)
        overlayController.dismiss(force: true)
    }

    private func queueAudioURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        Task { @MainActor in
            if appState.hasCompletedOnboarding {
                showOverlay()
            } else {
                showOnboardingWindow()
            }

            for url in urls {
                await TranscriptionQueue.shared.addFileToQueue(url: url)
            }
        }
    }

    private func isAudioFile(_ url: URL) -> Bool {
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType.conforms(to: .audio)
        }
        return UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) ?? false
    }

    private func observeMicrophoneChanges() {
        microphoneObserver = microphoneService.$availableMicrophones
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusBarMenu()
            }
    }

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            if let iconImage = NSImage(named: "tray_icon") {
                iconImage.size = NSSize(width: 48, height: 48)
                iconImage.isTemplate = true
                button.image = iconImage
            } else {
                button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "OpenSuperWhisper")
            }

            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self
        }

        updateStatusBarMenu()
    }

    private func updateStatusBarMenu() {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "OpenSuperWhisper", action: #selector(openApp), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let onboardingItem = NSMenuItem(title: "Open Onboarding", action: #selector(openOnboardingFromMenu), keyEquivalent: "")
        onboardingItem.target = self
        menu.addItem(onboardingItem)

        let transcriptionLanguageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        languageSubmenu = NSMenu()

        for languageCode in LanguageUtil.availableLanguages {
            let languageName = LanguageUtil.languageNames[languageCode] ?? languageCode
            let languageItem = NSMenuItem(title: languageName, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            languageItem.target = self
            languageItem.representedObject = languageCode
            languageItem.state = (AppPreferences.shared.whisperLanguage == languageCode) ? .on : .off
            languageSubmenu?.addItem(languageItem)
        }

        transcriptionLanguageItem.submenu = languageSubmenu
        menu.addItem(transcriptionLanguageItem)

        menu.addItem(NSMenuItem.separator())

        let microphoneMenu = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let microphones = microphoneService.availableMicrophones
        let currentMic = microphoneService.currentMicrophone

        if microphones.isEmpty {
            let noDeviceItem = NSMenuItem(title: "No microphones available", action: nil, keyEquivalent: "")
            noDeviceItem.isEnabled = false
            submenu.addItem(noDeviceItem)
        } else {
            let builtInMicrophones = microphones.filter(\.isBuiltIn)
            let externalMicrophones = microphones.filter { !$0.isBuiltIn }

            for microphone in builtInMicrophones {
                let item = NSMenuItem(
                    title: microphone.displayName,
                    action: #selector(selectMicrophone(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = microphone

                if let current = currentMic, current.id == microphone.id {
                    item.state = .on
                }

                submenu.addItem(item)
            }

            if !builtInMicrophones.isEmpty && !externalMicrophones.isEmpty {
                submenu.addItem(NSMenuItem.separator())
            }

            for microphone in externalMicrophones {
                let item = NSMenuItem(
                    title: microphone.displayName,
                    action: #selector(selectMicrophone(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = microphone

                if let current = currentMic, current.id == microphone.id {
                    item.state = .on
                }

                submenu.addItem(item)
            }
        }

        microphoneMenu.submenu = submenu
        menu.addItem(microphoneMenu)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func openSettingsWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? MicrophoneService.AudioDevice else { return }
        microphoneService.selectMicrophone(device)
        updateStatusBarMenu()
    }

    @objc private func statusBarButtonClicked(_ sender: Any) {
        statusItem?.button?.performClick(nil)
    }

    @objc private func openApp() {
        showOverlay()
    }

    @objc private func openSettingsFromMenu() {
        openSettingsWindow()
    }

    @objc private func openOnboardingFromMenu() {
        showOnboardingWindow()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let languageCode = sender.representedObject as? String else { return }

        AppPreferences.shared.whisperLanguage = languageCode

        if let submenu = sender.menu {
            for item in submenu.items {
                item.state = .off
            }
            sender.state = .on
        }
    }

    @objc private func languagePreferenceChanged() {
        updateLanguageMenuSelection()
    }

    private func updateLanguageMenuSelection() {
        guard let languageSubmenu = languageSubmenu else { return }

        let currentLanguage = AppPreferences.shared.whisperLanguage

        for item in languageSubmenu.items {
            if let languageCode = item.representedObject as? String {
                item.state = (languageCode == currentLanguage) ? .on : .off
            }
        }
    }
}
