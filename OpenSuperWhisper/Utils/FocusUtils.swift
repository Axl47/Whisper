//
//  FocusUtils.swift
//  OpenSuperWhisper
//
//  Created by user on 07.02.2025.
//

import AppKit
import ApplicationServices
import Carbon
import Cocoa
import Foundation
import KeyboardShortcuts
import SwiftUI

class FocusUtils {
    
    static func getCurrentCursorPosition() -> NSPoint {
        return NSEvent.mouseLocation
    }
    
    static func getCaretRect() -> CGRect? {
        // Получаем системный элемент для доступа ко всему UI
        let systemElement = AXUIElementCreateSystemWide()
        
        // Получаем фокусированный элемент
        var focusedElement: CFTypeRef? // Keep as CFTypeRef? if you prefer
        let errorFocused = AXUIElementCopyAttributeValue(systemElement,
                                                         kAXFocusedUIElementAttribute as CFString,
                                                         &focusedElement)
        
        print("errorFocused: \(errorFocused)")
        guard errorFocused == .success else {
            print("Не удалось получить фокусированный элемент")
            return nil
        }
        
        guard let focusedElementCF = focusedElement else { // Optional binding to safely unwrap CFTypeRef
            print("Не удалось получить фокусированный элемент (CFTypeRef is nil)") // Extra safety check, though unlikely
            return nil
        }
        
        let element = focusedElementCF as! AXUIElement
        // Получаем выделенный текстовый диапазон у фокусированного элемента
        var selectedTextRange: AnyObject?
        let errorRange = AXUIElementCopyAttributeValue(element,
                                                       kAXSelectedTextRangeAttribute as CFString,
                                                       &selectedTextRange)
        guard errorRange == .success,
              let textRange = selectedTextRange
        else {
            print("Не удалось получить диапазон выделенного текста")
            return nil
        }
        
        // Используем параметризованный атрибут для получения границ диапазона (положение каретки)
        var caretBounds: CFTypeRef?
        let errorBounds = AXUIElementCopyParameterizedAttributeValue(element,
                                                                     kAXBoundsForRangeParameterizedAttribute as CFString,
                                                                     textRange,
                                                                     &caretBounds)
        
        print("errorbounds: \(errorBounds), caretBounds \(String(describing: caretBounds))")
        guard errorBounds == .success else {
            print("Не удалось получить границы каретки")
            return nil
        }
        
        let rect = caretBounds as! AXValue
        
        return rect.toCGRect()
    }
    
    /// Converts a point from AX API coordinate system (Quartz: origin at top-left of primary screen, Y increases downward)
    /// to Cocoa coordinate system (origin at bottom-left of primary screen, Y increases upward)
    static func convertAXPointToCocoa(_ axPoint: CGPoint) -> NSPoint {
        guard let primaryScreen = NSScreen.screens.first else {
            return NSPoint(x: axPoint.x, y: axPoint.y)
        }
        // Primary screen maxY represents the total height in Cocoa coordinates
        // AX Y=0 is at Cocoa Y=maxY, so we subtract axPoint.y from maxY
        let cocoaY = primaryScreen.frame.maxY - axPoint.y
        return NSPoint(x: axPoint.x, y: cocoaY)
    }
    
    /// Finds the screen that contains the given point (in Cocoa coordinates)
    static func screenContaining(point: NSPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            if screen.frame.contains(point) {
                return screen
            }
        }
        return NSScreen.main
    }
    
    static func getFocusedWindowScreen() -> NSScreen? {
        let systemWideElement = AXUIElementCreateSystemWide()
        
        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWideElement,
                                                   kAXFocusedWindowAttribute as CFString,
                                                   &focusedWindow)
        
        guard result == .success else {
            print("Не удалось получить сфокусированное окно")
            return NSScreen.main
        }
        let windowElement = focusedWindow as! AXUIElement
        
        var windowFrameValue: CFTypeRef?
        let frameResult = AXUIElementCopyAttributeValue(windowElement,
                                                        
                                                        "AXFrame" as CFString,
                                                        &windowFrameValue)
        
        guard frameResult == .success else {
            print("Не удалось получить фрейм окна")
            return NSScreen.main
        }
        let frameValue = windowFrameValue as! AXValue
        
        var windowFrame = CGRect.zero
        guard AXValueGetValue(frameValue, AXValueType.cgRect, &windowFrame) else {
            print("Не удалось извлечь CGRect из AXValue")
            return NSScreen.main
        }
        
        for screen in NSScreen.screens {
            if screen.frame.intersects(windowFrame) {
                return screen
            }
        }
        
        return NSScreen.main
    }

    static func getFocusedElement() -> AXUIElement? {
        let systemElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard result == .success, let focusedElement else {
            return nil
        }

        return unsafeBitCast(focusedElement, to: AXUIElement.self)
    }

    static func frontmostApplicationPID() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    static func captureFocusedTextTarget() -> FocusedTextTargetSnapshot? {
        guard let element = getFocusedElement(),
              let appPID = frontmostApplicationPID()
        else {
            return nil
        }

        return FocusedTextTargetSnapshot(
            frontmostApplicationPID: appPID,
            element: element,
            selectedTextRange: selectedTextRange(for: element)
        )
    }

    static func appendText(
        _ text: String,
        to snapshot: FocusedTextTargetSnapshot,
        preferredSelectedRange: CFRange? = nil
    ) -> CFRange? {
        guard !text.isEmpty,
              snapshot.frontmostApplicationPID == frontmostApplicationPID(),
              let currentElement = getFocusedElement(),
              CFEqual(currentElement, snapshot.element)
        else {
            return nil
        }

        var isValueSettable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(
            snapshot.element,
            kAXValueAttribute as CFString,
            &isValueSettable
        )

        guard settableResult == .success, isValueSettable.boolValue else {
            return nil
        }

        let currentValue = stringValue(for: snapshot.element) ?? ""
        let selectedRange = preferredSelectedRange
            ?? snapshot.selectedTextRange
            ?? selectedTextRange(for: snapshot.element)
            ?? CFRange(location: currentValue.utf16.count, length: 0)

        let nsValue = currentValue as NSString
        let safeLocation = max(0, min(selectedRange.location, nsValue.length))
        let safeLength = max(0, min(selectedRange.length, nsValue.length - safeLocation))
        let insertionRange = NSRange(location: safeLocation, length: safeLength)
        let newValue = nsValue.replacingCharacters(in: insertionRange, with: text)

        let setValueResult = AXUIElementSetAttributeValue(
            snapshot.element,
            kAXValueAttribute as CFString,
            newValue as CFString
        )

        guard setValueResult == .success else {
            return nil
        }

        let insertedLength = (text as NSString).length
        let updatedRange = CFRange(location: safeLocation + insertedLength, length: 0)
        _ = setSelectedTextRange(updatedRange, for: snapshot.element)

        return updatedRange
    }

    static func stringValue(for element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard result == .success else {
            return nil
        }
        return value as? String
    }

    static func selectedTextRange(for element: AXUIElement) -> CFRange? {
        var selectedTextRange: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedTextRange
        )

        guard result == .success,
              let selectedTextRange
        else {
            return nil
        }

        let value = unsafeBitCast(selectedTextRange, to: AXValue.self)
        guard AXValueGetType(value) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range) else {
            return nil
        }

        return range
    }

    @discardableResult
    static func setSelectedTextRange(_ range: CFRange, for element: AXUIElement) -> Bool {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else {
            return false
        }

        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )

        return result == .success
    }

}

struct FocusedTextTargetSnapshot {
    let frontmostApplicationPID: pid_t
    let element: AXUIElement
    let selectedTextRange: CFRange?
}

struct BufferedTextInsertionState {
    private(set) var liveInsertionEnabled: Bool
    private(set) var bufferedText = ""

    init(liveInsertionEnabled: Bool) {
        self.liveInsertionEnabled = liveInsertionEnabled
    }

    mutating func recordCommittedDelta(_ text: String, insertedLive: Bool) {
        guard !text.isEmpty else { return }

        if liveInsertionEnabled && insertedLive {
            return
        }

        liveInsertionEnabled = false
        bufferedText += text
    }

    mutating func finalizeBufferedText() -> String? {
        guard !bufferedText.isEmpty else {
            return nil
        }

        let text = bufferedText
        bufferedText = ""
        return text
    }
}

@MainActor
final class FocusedTextInsertionSession {
    private let snapshot: FocusedTextTargetSnapshot?
    private let releaseInserter: @Sendable (String) -> Void
    private let liveInserter: (String, FocusedTextTargetSnapshot, CFRange?) -> CFRange?
    private var state: BufferedTextInsertionState
    private var nextSelectedTextRange: CFRange?

    init(
        snapshot: FocusedTextTargetSnapshot? = FocusUtils.captureFocusedTextTarget(),
        releaseInserter: @escaping @Sendable (String) -> Void = { ClipboardUtil.insertText($0) },
        liveInserter: @escaping (String, FocusedTextTargetSnapshot, CFRange?) -> CFRange? = {
            text, snapshot, preferredRange in
            FocusUtils.appendText(
                text,
                to: snapshot,
                preferredSelectedRange: preferredRange
            )
        }
    ) {
        self.snapshot = snapshot
        self.releaseInserter = releaseInserter
        self.liveInserter = liveInserter
        self.state = BufferedTextInsertionState(liveInsertionEnabled: snapshot != nil)
        self.nextSelectedTextRange = snapshot?.selectedTextRange
    }

    func appendCommittedDelta(_ text: String) {
        let insertedRange: CFRange?
        if let snapshot, state.liveInsertionEnabled {
            insertedRange = liveInserter(text, snapshot, nextSelectedTextRange)
        } else {
            insertedRange = nil
        }

        if let insertedRange {
            nextSelectedTextRange = insertedRange
        }

        state.recordCommittedDelta(text, insertedLive: insertedRange != nil)
    }

    @discardableResult
    func finalizeReleaseInsertion() -> String? {
        guard let text = state.finalizeBufferedText() else {
            return nil
        }

        releaseInserter(text)
        return text
    }
}

private extension AXValue {
    func toCGRect() -> CGRect? {
        var rect = CGRect.zero
        let type: AXValueType = AXValueGetType(self)
        
        guard type == .cgRect else {
            print("AXValue is not of type CGRect, but \(type)") // More informative error
            return nil
        }
        
        let success = AXValueGetValue(self, .cgRect, &rect)
        
        guard success else {
            print("Failed to get CGRect value from AXValue")
            return nil
        }
        return rect
    }
}
