import AppKit
import ApplicationServices
import Carbon
import Cocoa
import Foundation
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let toggleRecord = Self("toggleRecord", default: .init(.backtick, modifiers: .option))
    static let escape = Self("escape", default: .init(.escape))
}

enum ShortcutRecordingAction: Equatable {
    case none
    case start
    case stop
}

struct ShortcutRecordingInteractionState {
    private(set) var isSessionActive = false
    private(set) var hotkeyIsPressed = false
    private(set) var holdMode = false
    private(set) var handsFreeMode = false

    mutating func handleHotkeyDown(holdToRecordEnabled: Bool) -> ShortcutRecordingAction {
        hotkeyIsPressed = true

        if !isSessionActive {
            isSessionActive = true
            holdMode = false
            handsFreeMode = false
            return .start
        }

        if !holdToRecordEnabled || handsFreeMode || !holdMode {
            reset()
            return .stop
        }

        return .none
    }

    mutating func enableHoldModeIfNeeded() {
        guard isSessionActive, hotkeyIsPressed, !handsFreeMode else {
            return
        }
        holdMode = true
    }

    mutating func handleCommandDown(holdToRecordEnabled: Bool, supportsHandsFreeActivation: Bool) -> Bool {
        guard holdToRecordEnabled,
              supportsHandsFreeActivation,
              isSessionActive,
              hotkeyIsPressed,
              !handsFreeMode else {
            return false
        }

        handsFreeMode = true
        holdMode = true
        return true
    }

    mutating func handleHotkeyUp(holdToRecordEnabled: Bool) -> ShortcutRecordingAction {
        hotkeyIsPressed = false

        guard holdToRecordEnabled, isSessionActive, !handsFreeMode else {
            return .none
        }

        reset()
        return .stop
    }

    mutating func reset() {
        isSessionActive = false
        hotkeyIsPressed = false
        holdMode = false
        handsFreeMode = false
    }
}

class ShortcutManager {
    static let shared = ShortcutManager()

    private var activeVm: IndicatorViewModel?
    private var holdWorkItem: DispatchWorkItem?
    private let holdThreshold: TimeInterval = 0.3
    private var useModifierOnlyHotkey = false
    private var modifierOnlyHotkey: ModifierKey = .none
    private var interactionState = ShortcutRecordingInteractionState()
    private var globalModifierMonitor: Any?
    private var localModifierMonitor: Any?
    private var isCommandPressed = false

    private init() {
        print("ShortcutManager init")
        
        setupKeyboardShortcuts()
        setupModifierKeyMonitor()
        setupCommandModifierMonitor()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeySettingsChanged),
            name: .hotkeySettingsChanged,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(indicatorWindowDidHide),
            name: .indicatorWindowDidHide,
            object: nil
        )
    }
    
    @objc private func indicatorWindowDidHide() {
        activeVm = nil
        holdWorkItem?.cancel()
        holdWorkItem = nil
        interactionState.reset()
    }
    
    @objc private func hotkeySettingsChanged() {
        setupModifierKeyMonitor()
    }
    
    private func setupKeyboardShortcuts() {
        KeyboardShortcuts.onKeyDown(for: .toggleRecord) { [weak self] in
            self?.handleKeyDown()
        }

        KeyboardShortcuts.onKeyUp(for: .toggleRecord) { [weak self] in
            self?.handleKeyUp()
        }

        KeyboardShortcuts.onKeyUp(for: .escape) { [weak self] in
            Task { @MainActor in
                if self?.activeVm != nil {
                    IndicatorWindowManager.shared.stopForce()
                    self?.activeVm = nil
                }
            }
        }
        KeyboardShortcuts.disable(.escape)
    }
    
    private func setupModifierKeyMonitor() {
        let modifierKeyString = AppPreferences.shared.modifierOnlyHotkey
        let modifierKey = ModifierKey(rawValue: modifierKeyString) ?? .none
        modifierOnlyHotkey = modifierKey
        
        if modifierKey != .none {
            useModifierOnlyHotkey = true
            KeyboardShortcuts.disable(.toggleRecord)
            
            ModifierKeyMonitor.shared.onKeyDown = { [weak self] in
                self?.handleKeyDown()
            }
            
            ModifierKeyMonitor.shared.onKeyUp = { [weak self] in
                self?.handleKeyUp()
            }
            
            ModifierKeyMonitor.shared.start(modifierKey: modifierKey)
            print("ShortcutManager: Using modifier-only hotkey: \(modifierKey.displayName)")
        } else {
            useModifierOnlyHotkey = false
            ModifierKeyMonitor.shared.stop()
            KeyboardShortcuts.enable(.toggleRecord)
            print("ShortcutManager: Using regular keyboard shortcut")
        }
    }

    private func setupCommandModifierMonitor() {
        globalModifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierFlagsChanged(event.modifierFlags)
        }

        localModifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierFlagsChanged(event.modifierFlags)
            return event
        }
    }

    private func handleModifierFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        let commandPressedNow = flags.intersection(.deviceIndependentFlagsMask).contains(.command)
        guard commandPressedNow != isCommandPressed else {
            return
        }

        isCommandPressed = commandPressedNow
        guard commandPressedNow else {
            return
        }

        let holdToRecordEnabled = AppPreferences.shared.holdToRecord
        let supportsHandsFreeActivation = !(useModifierOnlyHotkey && modifierOnlyHotkey.cgEventFlag == .maskCommand)

        guard interactionState.handleCommandDown(
            holdToRecordEnabled: holdToRecordEnabled,
            supportsHandsFreeActivation: supportsHandsFreeActivation
        ) else {
            return
        }

        holdWorkItem?.cancel()
        holdWorkItem = nil

        Task { @MainActor in
            self.activeVm?.setHandsFreeMode(true)
        }
    }
    
    private func handleKeyDown() {
        holdWorkItem?.cancel()
        
        let holdToRecordEnabled = AppPreferences.shared.holdToRecord
        let action = interactionState.handleHotkeyDown(holdToRecordEnabled: holdToRecordEnabled)
        
        Task { @MainActor in
            switch action {
            case .start:
                let cursorPosition = FocusUtils.getCurrentCursorPosition()
                let indicatorPoint: NSPoint?
                if let caret = FocusUtils.getCaretRect() {
                    indicatorPoint = FocusUtils.convertAXPointToCocoa(caret.origin)
                } else {
                    indicatorPoint = cursorPosition
                }
                let vm = IndicatorWindowManager.shared.show(nearPoint: indicatorPoint)
                vm.startRecording()
                vm.setHandsFreeMode(false)
                self.activeVm = vm
            case .stop:
                IndicatorWindowManager.shared.stopRecording()
                self.activeVm = nil
            case .none:
                break
            }
        }
        
        if action == .start && holdToRecordEnabled {
            let workItem = DispatchWorkItem { [weak self] in
                self?.interactionState.enableHoldModeIfNeeded()
            }
            holdWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold, execute: workItem)
        }
    }
    
    private func handleKeyUp() {
        holdWorkItem?.cancel()
        holdWorkItem = nil
        
        let holdToRecordEnabled = AppPreferences.shared.holdToRecord
        let action = interactionState.handleHotkeyUp(holdToRecordEnabled: holdToRecordEnabled)
        
        Task { @MainActor in
            if action == .stop {
                IndicatorWindowManager.shared.stopRecording()
                self.activeVm = nil
            }
        }
    }
}
