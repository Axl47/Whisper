//
//  OpenSuperWhisperTests.swift
//  OpenSuperWhisperTests
//
//  Created by user on 05.02.2025.
//

import XCTest
import Carbon
import ApplicationServices
import AVFoundation
@testable import OpenSuperWhisper

final class OpenSuperWhisperTests: XCTestCase {

    override func setUpWithError() throws {
    }

    override func tearDownWithError() throws {
    }

    func testPerformanceExample() throws {
        self.measure {
        }
    }
}

final class WhisperEngineMultiChannelTests: XCTestCase {
    func testMakeTargetFormat_withSixChannels_returnsFormat() {
        let engine = WhisperEngine()
        let format = engine.makeTargetFormat(channelCount: 6)
        
        XCTAssertNotNil(format)
        XCTAssertEqual(format?.channelCount, 6)
        XCTAssertEqual(format?.sampleRate, 16000)
    }
    
    func testMakeTargetFormat_withZeroChannels_returnsNil() {
        let engine = WhisperEngine()
        XCTAssertNil(engine.makeTargetFormat(channelCount: 0))
    }
}

final class MicrophoneInventoryTests: XCTestCase {
    
    func testPrintConnectedMicrophones() throws {
        let service = MicrophoneService.shared
        service.refreshAvailableMicrophones()
        let available = service.availableMicrophones
        print("Available microphones count: \(available.count)")
        for device in available {
            print("Microphone:")
            print("  name: \(device.name)")
            print("  id: \(device.id)")
            print("  manufacturer: \(device.manufacturer ?? "nil")")
            print("  isBuiltIn: \(device.isBuiltIn)")
            print("  isContinuity: \(service.isContinuityMicrophone(device))")
            print("  isBluetooth: \(service.isBluetoothMicrophone(device))")
        }
        
        let deviceTypes: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            deviceTypes = [.microphone, .external]
        } else {
            deviceTypes = [.microphone, .external, .builtInMicrophone]
        }
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .audio,
            position: .unspecified
        )
        
        print("AVCaptureDevice count: \(discoverySession.devices.count)")
        for device in discoverySession.devices {
            print("AVCaptureDevice:")
            print("  localizedName: \(device.localizedName)")
            print("  uniqueID: \(device.uniqueID)")
            print("  manufacturer: \(device.manufacturer)")
            print("  deviceType: \(device.deviceType.rawValue)")
            if #available(macOS 13.0, *) {
                print("  isConnected: \(device.isConnected)")
            }
            print("  transportType: \(device.transportType)")
        }
    }
}

// MARK: - Keyboard Layout Tests

final class ClipboardUtilKeyboardLayoutTests: XCTestCase {
    
    private var originalInputSourceID: String?
    
    override func setUpWithError() throws {
        originalInputSourceID = ClipboardUtil.getCurrentInputSourceID()
    }
    
    override func tearDownWithError() throws {
        if let originalID = originalInputSourceID {
            _ = ClipboardUtil.switchToInputSource(withID: originalID)
        }
    }
    
    func testGetAvailableInputSources() throws {
        let sources = ClipboardUtil.getAvailableInputSources()
        XCTAssertFalse(sources.isEmpty, "Should have at least one input source")
        print("Available input sources: \(sources)")
    }
    
    func testGetCurrentInputSourceID() throws {
        let currentID = ClipboardUtil.getCurrentInputSourceID()
        XCTAssertNotNil(currentID, "Should be able to get current input source ID")
        print("Current input source: \(currentID ?? "nil")")
    }
    
    func testFindKeycodeForV_USLayout() throws {
        let switched = ClipboardUtil.switchToInputSource(withID: "US")
        if !switched {
            throw XCTSkip("US layout not available")
        }
        
        let keycode = ClipboardUtil.findKeycodeForCharacter("v")
        XCTAssertNotNil(keycode, "Should find keycode for 'v' in US layout")
        XCTAssertEqual(keycode, 9, "Keycode for 'v' in US QWERTY should be 9")
    }
    
    func testFindKeycodeForV_DvorakQwertyLayout() throws {
        let switched = ClipboardUtil.switchToInputSource(withID: "DVORAK-QWERTYCMD")
        if !switched {
            throw XCTSkip("Dvorak-QWERTY layout not available")
        }
        
        let keycode = ClipboardUtil.findKeycodeForCharacter("v")
        XCTAssertNotNil(keycode, "Should find keycode for 'v' in Dvorak-QWERTY layout")
        print("Dvorak-QWERTY keycode for 'v': \(keycode ?? 0)")
    }
    
    func testFindKeycodeForV_DvorakLeftHand() throws {
        let switched = ClipboardUtil.switchToInputSource(withID: "Dvorak-Left")
        if !switched {
            throw XCTSkip("Dvorak Left-Handed layout not available")
        }
        
        let keycode = ClipboardUtil.findKeycodeForCharacter("v")
        XCTAssertNotNil(keycode, "Should find keycode for 'v' in Dvorak Left-Handed layout")
        print("Dvorak Left-Handed keycode for 'v': \(keycode ?? 0)")
    }
    
    func testFindKeycodeForV_DvorakRightHand() throws {
        let switched = ClipboardUtil.switchToInputSource(withID: "Dvorak-Right")
        if !switched {
            throw XCTSkip("Dvorak Right-Handed layout not available")
        }
        
        let keycode = ClipboardUtil.findKeycodeForCharacter("v")
        XCTAssertNotNil(keycode, "Should find keycode for 'v' in Dvorak Right-Handed layout")
        print("Dvorak Right-Handed keycode for 'v': \(keycode ?? 0)")
    }
    
    func testFindKeycodeForV_RussianLayout() throws {
        let switched = ClipboardUtil.switchToInputSource(withID: "Russian")
        if !switched {
            throw XCTSkip("Russian layout not available")
        }
        
        let keycode = ClipboardUtil.findKeycodeForCharacter("v")
        XCTAssertNil(keycode, "Should NOT find keycode for 'v' in Russian layout (no Latin 'v')")
    }
    
    func testIsQwertyCommandLayout_USLayout() throws {
        let switched = ClipboardUtil.switchToInputSource(withID: "US")
        if !switched {
            throw XCTSkip("US layout not available")
        }
        
        XCTAssertTrue(ClipboardUtil.isQwertyCommandLayout(), "US layout should be detected as QWERTY command layout")
    }
    
    func testIsQwertyCommandLayout_DvorakQwerty() throws {
        let switched = ClipboardUtil.switchToInputSource(withID: "DVORAK-QWERTYCMD")
        if !switched {
            throw XCTSkip("Dvorak-QWERTY layout not available")
        }
        
        XCTAssertTrue(ClipboardUtil.isQwertyCommandLayout(), "Dvorak-QWERTY should be detected as QWERTY command layout")
    }
    
    func testIsQwertyCommandLayout_DvorakLeftHand() throws {
        let switched = ClipboardUtil.switchToInputSource(withID: "Dvorak-Left")
        if !switched {
            throw XCTSkip("Dvorak Left-Handed layout not available")
        }
        
        XCTAssertFalse(ClipboardUtil.isQwertyCommandLayout(), "Dvorak Left-Handed should NOT be detected as QWERTY command layout")
    }
    
    func testIsQwertyCommandLayout_DvorakRightHand() throws {
        let switched = ClipboardUtil.switchToInputSource(withID: "Dvorak-Right")
        if !switched {
            throw XCTSkip("Dvorak Right-Handed layout not available")
        }
        
        XCTAssertFalse(ClipboardUtil.isQwertyCommandLayout(), "Dvorak Right-Handed should NOT be detected as QWERTY command layout")
    }
}

final class MicrophoneServiceContinuityTests: XCTestCase {
    
    func testContinuityDetection_iPhoneApple() {
        let device = MicrophoneService.AudioDevice(
            id: "com.apple.continuity.iphone",
            name: "iPhone Microphone",
            manufacturer: "Apple",
            isBuiltIn: false
        )
        XCTAssertTrue(MicrophoneService.shared.isContinuityMicrophone(device))
    }
    
    func testContinuityDetection_ContinuityApple() {
        let device = MicrophoneService.AudioDevice(
            id: "com.apple.continuity.mic",
            name: "Continuity Microphone",
            manufacturer: "Apple",
            isBuiltIn: false
        )
        XCTAssertTrue(MicrophoneService.shared.isContinuityMicrophone(device))
    }
    
    func testContinuityDetection_NotApple() {
        let device = MicrophoneService.AudioDevice(
            id: "com.vendor.iphone",
            name: "iPhone Microphone",
            manufacturer: "Vendor",
            isBuiltIn: false
        )
        XCTAssertFalse(MicrophoneService.shared.isContinuityMicrophone(device))
    }
    
    func testContinuityDetection_AppleBuiltIn() {
        let device = MicrophoneService.AudioDevice(
            id: "builtin",
            name: "MacBook Pro Microphone",
            manufacturer: "Apple",
            isBuiltIn: true
        )
        XCTAssertFalse(MicrophoneService.shared.isContinuityMicrophone(device))
    }
}

final class MicrophoneServiceBluetoothTests: XCTestCase {
    
    func testBluetoothDetection_BluetoothInName() {
        let device = MicrophoneService.AudioDevice(
            id: "some-id",
            name: "Bluetooth Headphones",
            manufacturer: "Apple",
            isBuiltIn: false
        )
        XCTAssertTrue(MicrophoneService.shared.isBluetoothMicrophone(device))
    }
    
    func testBluetoothDetection_BluetoothInID() {
        let device = MicrophoneService.AudioDevice(
            id: "bluetooth-device-123",
            name: "Headphones",
            manufacturer: "Apple",
            isBuiltIn: false
        )
        XCTAssertTrue(MicrophoneService.shared.isBluetoothMicrophone(device))
    }
    
    func testBluetoothDetection_MACAddress() {
        let device = MicrophoneService.AudioDevice(
            id: "00-22-BB-71-21-0A:input",
            name: "Amiron wireless",
            manufacturer: "Apple",
            isBuiltIn: false
        )
        XCTAssertTrue(MicrophoneService.shared.isBluetoothMicrophone(device))
    }
    
    func testBluetoothDetection_NotBluetooth() {
        let device = MicrophoneService.AudioDevice(
            id: "builtin",
            name: "MacBook Pro Microphone",
            manufacturer: "Apple",
            isBuiltIn: true
        )
        XCTAssertFalse(MicrophoneService.shared.isBluetoothMicrophone(device))
    }
}

final class MicrophoneServiceRequiresConnectionTests: XCTestCase {
    
    func testRequiresConnection_iPhone() {
        let device = MicrophoneService.AudioDevice(
            id: "B95EA61C-AC67-43B3-8AB4-8AE800000003",
            name: "Микрофон (iPhone nagibator)",
            manufacturer: "Apple Inc.",
            isBuiltIn: false
        )
        XCTAssertTrue(MicrophoneService.shared.isContinuityMicrophone(device))
        XCTAssertTrue(MicrophoneService.shared.isBluetoothMicrophone(device) || MicrophoneService.shared.isContinuityMicrophone(device))
    }
    
    func testRequiresConnection_Bluetooth() {
        let device = MicrophoneService.AudioDevice(
            id: "00-22-BB-71-21-0A:input",
            name: "Amiron wireless",
            manufacturer: "Apple",
            isBuiltIn: false
        )
        XCTAssertTrue(MicrophoneService.shared.isBluetoothMicrophone(device))
    }
    
    func testRequiresConnection_BuiltIn() {
        let device = MicrophoneService.AudioDevice(
            id: "BuiltInMicrophoneDevice",
            name: "Микрофон MacBook Pro",
            manufacturer: "Apple Inc.",
            isBuiltIn: true
        )
        XCTAssertFalse(MicrophoneService.shared.isContinuityMicrophone(device))
        XCTAssertFalse(MicrophoneService.shared.isBluetoothMicrophone(device))
    }
}

// MARK: - Paste Integration Tests

final class ClipboardUtilPasteIntegrationTests: XCTestCase {
    
    private static var sharedTextEditProcess: NSRunningApplication?
    private static var sharedAppElement: AXUIElement?
    private static var originalInputSourceID: String?
    private static var testCounter = 0
    
    private func log(_ message: String) {
        let logMessage = "[TEST \(Date())] \(message)\n"
        print(logMessage)
        let logFile = "/tmp/paste_test_log.txt"
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile) {
                if let handle = FileHandle(forWritingAtPath: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logFile, contents: data)
            }
        }
    }
    
    override class func setUp() {
        super.setUp()
        print("[TEST] ========== CLASS SETUP ==========")
        originalInputSourceID = ClipboardUtil.getCurrentInputSourceID()
        print("[TEST] Original layout: \(originalInputSourceID ?? "nil")")
        
        _ = ClipboardUtil.switchToInputSource(withID: "US")
        print("[TEST] Switched to US layout for setup")
        
        terminateTextEditIfRunning()
        testCounter = 0
    }
    
    override class func tearDown() {
        print("[TEST] ========== CLASS TEARDOWN ==========")
        if let originalID = originalInputSourceID {
            _ = ClipboardUtil.switchToInputSource(withID: originalID)
        }
        terminateTextEditIfRunning()
        sharedTextEditProcess = nil
        sharedAppElement = nil
        super.tearDown()
    }
    
    override func setUpWithError() throws {
        Self.testCounter += 1
        log("--- Test #\(Self.testCounter) SETUP ---")
        try super.setUpWithError()
    }
    
    override func tearDownWithError() throws {
        log("--- Test #\(Self.testCounter) TEARDOWN ---")
        try super.tearDownWithError()
    }
    
    private static func terminateTextEditIfRunning() {
        let runningApps = NSWorkspace.shared.runningApplications
        var terminated = false
        for app in runningApps where app.bundleIdentifier == "com.apple.TextEdit" {
            print("[TEST] Force terminating TextEdit (pid: \(app.processIdentifier))")
            app.forceTerminate()
            terminated = true
        }
        if terminated {
            Thread.sleep(forTimeInterval: 0.5)
        }
        sharedTextEditProcess = nil
        sharedAppElement = nil
    }
    
    private func terminateTextEditIfRunning() {
        Self.terminateTextEditIfRunning()
    }
    
    private func launchTextEditIfNeeded() throws -> AXUIElement {
        if let appElement = Self.sharedAppElement,
           let process = Self.sharedTextEditProcess,
           !process.isTerminated {
            log("TextEdit already running (pid: \(process.processIdentifier))")
            return appElement
        }
        
        log("Launching TextEdit...")
        let workspace = NSWorkspace.shared
        
        guard let textEditURL = workspace.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else {
            throw XCTSkip("TextEdit not found")
        }
        
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        
        let semaphore = DispatchSemaphore(value: 0)
        var launchedApp: NSRunningApplication?
        
        workspace.openApplication(at: textEditURL, configuration: configuration) { app, error in
            launchedApp = app
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 5.0)
        
        guard let app = launchedApp else {
            throw XCTSkip("Failed to launch TextEdit")
        }
        
        log("TextEdit launched (pid: \(app.processIdentifier))")
        Self.sharedTextEditProcess = app
        Thread.sleep(forTimeInterval: 1.0)
        Self.sharedAppElement = AXUIElementCreateApplication(app.processIdentifier)
        
        dismissOpenDialogIfPresent()
        createNewDocumentIfNeeded()
        
        return Self.sharedAppElement!
    }
    
    private func activateTextEdit() {
        Self.sharedTextEditProcess?.activate()
        Thread.sleep(forTimeInterval: 0.3)
    }
    
    private func sendKeyStroke(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }
        
        keyDown.flags = flags
        keyUp.flags = flags
        
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
    
    private func dismissOpenDialogIfPresent() {
        log("Dismissing open dialog if present...")
        activateTextEdit()
        sendKeyStroke(keyCode: 53)
        Thread.sleep(forTimeInterval: 0.5)
        sendKeyStroke(keyCode: 53)
        Thread.sleep(forTimeInterval: 0.3)
    }
    
    private func createNewDocumentIfNeeded() {
        log("Creating new document...")
        activateTextEdit()
        sendKeyStroke(keyCode: 45, flags: .maskCommand)
        Thread.sleep(forTimeInterval: 1.0)
        
        clickInTextArea()
    }
    
    private func clickInTextArea() {
        log("Clicking in text area...")
        guard let process = Self.sharedTextEditProcess else { return }
        
        let appElement = AXUIElementCreateApplication(process.processIdentifier)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowValue) == .success,
              let windows = windowValue as? [AXUIElement],
              let mainWindow = windows.first else {
            log("No windows found")
            return
        }
        
        var scrollAreaValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(mainWindow, kAXChildrenAttribute as CFString, &scrollAreaValue) == .success,
           let children = scrollAreaValue as? [AXUIElement] {
            for child in children {
                var roleValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue) == .success,
                   let role = roleValue as? String,
                   role == "AXScrollArea" {
                    var textAreaValue: CFTypeRef?
                    if AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &textAreaValue) == .success,
                       let textAreaChildren = textAreaValue as? [AXUIElement] {
                        for textChild in textAreaChildren {
                            var textRoleValue: CFTypeRef?
                            if AXUIElementCopyAttributeValue(textChild, kAXRoleAttribute as CFString, &textRoleValue) == .success,
                               let textRole = textRoleValue as? String,
                               textRole == "AXTextArea" {
                                log("Found text area, setting focus...")
                                AXUIElementSetAttributeValue(textChild, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                                Thread.sleep(forTimeInterval: 0.3)
                                return
                            }
                        }
                    }
                }
            }
        }
        log("Text area not found, clicking in center of window...")
    }
    
    private func selectAllAndDelete() {
        log("Selecting all and deleting...")
        activateTextEdit()
        sendKeyStroke(keyCode: 0, flags: .maskCommand)
        Thread.sleep(forTimeInterval: 0.1)
        sendKeyStroke(keyCode: 51)
        Thread.sleep(forTimeInterval: 0.2)
    }
    
    // MARK: - Basic Layouts
    
    func testPasteWithUSLayout() throws {
        try testPasteWithLayout(layoutID: "US", testText: "Hello from US layout test")
    }
    
    func testPasteWithABCLayout() throws {
        try testPasteWithLayout(layoutID: "ABC", testText: "Hello from ABC layout test")
    }
    
    func testPasteWithUSInternationalLayout() throws {
        try testPasteWithLayout(layoutID: "USInternational", testText: "Hello from US International layout test")
    }
    
    func testPasteWithBritishLayout() throws {
        try testPasteWithLayout(layoutID: "British", testText: "Hello from British layout test")
    }
    
    func testPasteWithColemakLayout() throws {
        try testPasteWithLayout(layoutID: "Colemak", testText: "Hello from Colemak layout test")
    }
    
    // MARK: - Dvorak Layouts
    
    func testPasteWithDvorakQwertyLayout() throws {
        try testPasteWithLayout(layoutID: "DVORAK-QWERTYCMD", testText: "Hello from Dvorak-QWERTY layout test")
    }
    
    func testPasteWithDvorakLeftHandLayout() throws {
        try testPasteWithLayout(layoutID: "Dvorak-Left", testText: "Hello from Dvorak Left-Handed layout test")
    }
    
    func testPasteWithDvorakRightHandLayout() throws {
        try testPasteWithLayout(layoutID: "Dvorak-Right", testText: "Hello from Dvorak Right-Handed layout test")
    }
    
    // MARK: - Cyrillic Layouts
    
    func testPasteWithRussianLayout() throws {
        try testPasteWithLayout(layoutID: "Russian", testText: "Привет из теста русской раскладки")
    }
    
    func testPasteWithUkrainianLayout() throws {
        try testPasteWithLayout(layoutID: "Ukrainian", testText: "Привіт з тесту української розкладки")
    }
    
    // MARK: - European Layouts
    
    func testPasteWithGermanLayout() throws {
        try testPasteWithLayout(layoutID: "German", testText: "Hallo aus dem deutschen Layout-Test")
    }
    
    func testPasteWithFrenchLayout() throws {
        try testPasteWithLayout(layoutID: "French", testText: "Bonjour du test de disposition française")
    }
    
    func testPasteWithSpanishLayout() throws {
        try testPasteWithLayout(layoutID: "Spanish", testText: "Hola desde la prueba de teclado español")
    }
    
    func testPasteWithItalianLayout() throws {
        try testPasteWithLayout(layoutID: "Italian", testText: "Ciao dal test del layout italiano")
    }
    
    func testPasteWithPortugueseLayout() throws {
        try testPasteWithLayout(layoutID: "Portuguese", testText: "Olá do teste de layout português")
    }
    
    func testPasteWithPolishLayout() throws {
        try testPasteWithLayout(layoutID: "Polish", testText: "Cześć z testu polskiego układu")
    }
    
    func testPasteWithGreekLayout() throws {
        try testPasteWithLayout(layoutID: "Greek", testText: "Γειά σου από τη δοκιμή ελληνικής διάταξης")
    }
    
    func testPasteWithTurkishLayout() throws {
        try testPasteWithLayout(layoutID: "Turkish", testText: "Türkçe klavye testinden merhaba")
    }
    
    func testPasteWithSwissGermanLayout() throws {
        try testPasteWithLayout(layoutID: "Swiss German", testText: "Grüezi vom Schweizer Layout-Test")
    }
    
    func testPasteWithDutchLayout() throws {
        try testPasteWithLayout(layoutID: "Dutch", testText: "Hallo van de Nederlandse layout test")
    }
    
    func testPasteWithSwedishLayout() throws {
        try testPasteWithLayout(layoutID: "Swedish", testText: "Hej från det svenska layouttestet")
    }
    
    func testPasteWithNorwegianLayout() throws {
        try testPasteWithLayout(layoutID: "Norwegian", testText: "Hei fra den norske layouttesten")
    }
    
    func testPasteWithDanishLayout() throws {
        try testPasteWithLayout(layoutID: "Danish", testText: "Hej fra den danske layouttest")
    }
    
    func testPasteWithFinnishLayout() throws {
        try testPasteWithLayout(layoutID: "Finnish", testText: "Terve suomalaisesta näppäimistötestistä")
    }
    
    func testPasteWithCzechLayout() throws {
        try testPasteWithLayout(layoutID: "Czech", testText: "Ahoj z testu českého rozložení")
    }
    
    func testPasteWithHungarianLayout() throws {
        try testPasteWithLayout(layoutID: "Hungarian", testText: "Helló a magyar billentyűzet tesztből")
    }
    
    func testPasteWithRomanianLayout() throws {
        try testPasteWithLayout(layoutID: "Romanian", testText: "Bună din testul de layout românesc")
    }
    
    // MARK: - Asian Layouts
    
    func testPasteWithChinesePinyinLayout() throws {
        try testPasteWithLayout(layoutID: "Pinyin", testText: "你好从中文拼音布局测试")
    }
    
    func testPasteWithChineseTraditionalLayout() throws {
        try testPasteWithLayout(layoutID: "Traditional", testText: "你好從繁體中文佈局測試")
    }
    
    func testPasteWithJapaneseLayout() throws {
        try testPasteWithLayout(layoutID: "Japanese", testText: "こんにちは日本語レイアウトテストから")
    }
    
    func testPasteWithJapaneseRomajiLayout() throws {
        try testPasteWithLayout(layoutID: "Romaji", testText: "Hello from Japanese Romaji layout test")
    }
    
    func testPasteWithKoreanLayout() throws {
        try testPasteWithLayout(layoutID: "Korean", testText: "안녕하세요 한국어 레이아웃 테스트에서")
    }
    
    func testPasteWithVietnameseLayout() throws {
        try testPasteWithLayout(layoutID: "Vietnamese", testText: "Xin chào từ bài kiểm tra bố cục tiếng Việt")
    }
    
    func testPasteWithThaiLayout() throws {
        try testPasteWithLayout(layoutID: "Thai", testText: "สวัสดีจากการทดสอบคีย์บอร์ดภาษาไทย")
    }
    
    // MARK: - Middle Eastern Layouts
    
    func testPasteWithArabicLayout() throws {
        try testPasteWithLayout(layoutID: "Arabic", testText: "مرحبا من اختبار تخطيط اللغة العربية")
    }
    
    func testPasteWithHebrewLayout() throws {
        try testPasteWithLayout(layoutID: "Hebrew", testText: "שלום ממבחן פריסת עברית")
    }
    
    func testPasteWithPersianLayout() throws {
        try testPasteWithLayout(layoutID: "Persian", testText: "سلام از آزمایش چیدمان فارسی")
    }
    
    // MARK: - Helper Method
    
    private func testPasteWithLayout(layoutID: String, testText: String) throws {
        log("Testing layout: \(layoutID)")
        
        _ = ClipboardUtil.switchToInputSource(withID: "US")
        log("Switched to US for TextEdit operations")
        
        _ = try launchTextEditIfNeeded()
        selectAllAndDelete()
        activateTextEdit()
        
        let switched = ClipboardUtil.switchToInputSource(withID: layoutID)
        if !switched {
            log("Layout \(layoutID) not available, skipping")
            throw XCTSkip("\(layoutID) layout not available")
        }
        log("Switched to layout: \(layoutID)")
        
        Thread.sleep(forTimeInterval: 0.2)
        
        activateTextEdit()
        clickInTextArea()
        
        log("Inserting text: \(testText)")
        ClipboardUtil.insertText(testText)
        
        Thread.sleep(forTimeInterval: 0.5)
        
        activateTextEdit()
        Thread.sleep(forTimeInterval: 0.2)
        
        let resultText = getTextFromTextEdit()
        log("Result text: \(resultText ?? "nil")")
        XCTAssertEqual(resultText, testText, "Text should be pasted correctly with \(layoutID) layout")
    }
    
    private func getTextFromTextEdit() -> String? {
        guard let process = Self.sharedTextEditProcess else { return nil }
        
        let appElement = AXUIElementCreateApplication(process.processIdentifier)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowValue) == .success,
              let windows = windowValue as? [AXUIElement],
              let mainWindow = windows.first else {
            return nil
        }
        
        var scrollAreaValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(mainWindow, kAXChildrenAttribute as CFString, &scrollAreaValue) == .success,
           let children = scrollAreaValue as? [AXUIElement] {
            for child in children {
                var roleValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue) == .success,
                   let role = roleValue as? String,
                   role == "AXScrollArea" {
                    var textAreaValue: CFTypeRef?
                    if AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &textAreaValue) == .success,
                       let textAreaChildren = textAreaValue as? [AXUIElement] {
                        for textChild in textAreaChildren {
                            var textRoleValue: CFTypeRef?
                            if AXUIElementCopyAttributeValue(textChild, kAXRoleAttribute as CFString, &textRoleValue) == .success,
                               let textRole = textRoleValue as? String,
                               textRole == "AXTextArea" {
                                var valueRef: CFTypeRef?
                                if AXUIElementCopyAttributeValue(textChild, kAXValueAttribute as CFString, &valueRef) == .success,
                                   let text = valueRef as? String {
                                    return text
                                }
                            }
                        }
                    }
                }
            }
        }
        return nil
    }
    
    func testPasteAllAvailableLayouts() throws {
        log("Testing all available layouts")
        let layouts = ClipboardUtil.getAvailableInputSources()
        log("Available layouts: \(layouts)")
        var results: [(layout: String, success: Bool, error: String?)] = []
        
        for layout in layouts {
            log("Testing layout: \(layout)")
            
            _ = ClipboardUtil.switchToInputSource(withID: "US")
            
            _ = try launchTextEditIfNeeded()
            selectAllAndDelete()
            activateTextEdit()
            
            let switched = ClipboardUtil.switchToInputSource(withID: layout)
            if !switched {
                log("Failed to switch to \(layout)")
                results.append((layout, false, "Failed to switch"))
                continue
            }
            
            Thread.sleep(forTimeInterval: 0.2)
            
            activateTextEdit()
            clickInTextArea()
            
            let testText = "Test for \(layout)"
            ClipboardUtil.insertText(testText)
            
            Thread.sleep(forTimeInterval: 0.5)
            
            activateTextEdit()
            Thread.sleep(forTimeInterval: 0.2)
            
            let resultText = getTextFromTextEdit() ?? ""
            let success = resultText == testText
            log("Layout \(layout): expected '\(testText)', got '\(resultText)' - \(success ? "OK" : "FAIL")")
            results.append((layout, success, success ? nil : "Expected '\(testText)', got '\(resultText)'"))
        }
        
        print("\n=== Paste Test Results ===")
        for result in results {
            let status = result.success ? "✅" : "❌"
            print("\(status) \(result.layout): \(result.error ?? "OK")")
        }
        print("===========================\n")
        
        let failedLayouts = results.filter { !$0.success }
        XCTAssertTrue(failedLayouts.isEmpty, "Failed layouts: \(failedLayouts.map { $0.layout })")
    }
}

// MARK: - Keyboard Layout Provider Tests

final class KeyboardLayoutProviderTests: XCTestCase {
    
    private let provider = KeyboardLayoutProvider.shared
    private var originalInputSourceID: String?
    
    override func setUpWithError() throws {
        originalInputSourceID = ClipboardUtil.getCurrentInputSourceID()
    }
    
    override func tearDownWithError() throws {
        if let originalID = originalInputSourceID {
            _ = ClipboardUtil.switchToInputSource(withID: originalID)
        }
    }
    
    // MARK: - Physical Type Detection
    
    func testDetectPhysicalType_returnsValue() {
        let physicalType = provider.detectPhysicalType()
        print("Detected physical keyboard type: \(physicalType)")
        XCTAssertTrue([.ansi, .iso, .jis].contains(physicalType))
    }
    
    // MARK: - Label Resolution
    
    func testResolveLabels_returnsLabelsForCurrentLayout() {
        let labels = provider.resolveLabels()
        XCTAssertNotNil(labels, "Should resolve labels for current layout")
        if let labels = labels {
            XCTAssertEqual(labels.count, KeyboardLayoutProvider.ansiKeycodes.count,
                           "Should have a label for every ANSI keycode")
        }
    }
    
    func testResolveLabels_USLayout_hasExpectedKeys() throws {
        let switched = ClipboardUtil.switchToInputSource(withID: "US")
        if !switched { throw XCTSkip("US layout not available") }
        
        let labels = provider.resolveLabels()
        XCTAssertNotNil(labels)
        guard let labels = labels else { return }
        
        XCTAssertEqual(labels[0], "A", "Keycode 0 should be A in US layout")
        XCTAssertEqual(labels[1], "S", "Keycode 1 should be S in US layout")
        XCTAssertEqual(labels[13], "W", "Keycode 13 should be W in US layout")
        XCTAssertEqual(labels[50], "`", "Keycode 50 should be ` in US layout")
    }
    
    func testResolveLabels_RussianLayout_hasCyrillicKeys() throws {
        let switched = ClipboardUtil.switchToInputSource(withID: "Russian")
        if !switched { throw XCTSkip("Russian layout not available") }
        
        let labels = provider.resolveLabels()
        XCTAssertNotNil(labels)
        guard let labels = labels else { return }
        
        XCTAssertEqual(labels[0], "Ф", "Keycode 0 should be Ф in Russian layout")
        XCTAssertEqual(labels[1], "Ы", "Keycode 1 should be Ы in Russian layout")
    }
    
    // MARK: - resolveInfo (full validation)
    
    func testResolveInfo_USLayout_returnsInfo() throws {
        let switched = ClipboardUtil.switchToInputSource(withID: "US")
        if !switched { throw XCTSkip("US layout not available") }
        
        let info = provider.resolveInfo()
        if provider.detectPhysicalType() == .ansi {
            XCTAssertNotNil(info, "US layout on ANSI keyboard should produce info")
        }
    }
    
    func testResolveInfo_RussianLayout_returnsInfo() throws {
        let switched = ClipboardUtil.switchToInputSource(withID: "Russian")
        if !switched { throw XCTSkip("Russian layout not available") }
        
        let info = provider.resolveInfo()
        if provider.detectPhysicalType() == .ansi {
            XCTAssertNotNil(info, "Russian layout on ANSI keyboard should produce info (Cyrillic labels)")
        }
    }
    
    func testResolveInfo_GermanLayout_returnsInfo() throws {
        let switched = ClipboardUtil.switchToInputSource(withID: "German")
        if !switched { throw XCTSkip("German layout not available") }
        
        let info = provider.resolveInfo()
        if provider.detectPhysicalType() == .ansi {
            XCTAssertNotNil(info, "German layout on ANSI keyboard should produce info")
        }
    }
    
    func testResolveInfo_nonANSI_returnsNil() throws {
        let physicalType = provider.detectPhysicalType()
        if physicalType != .ansi {
            let info = provider.resolveInfo()
            XCTAssertNil(info, "Non-ANSI physical keyboard should return nil from resolveInfo")
        } else {
            throw XCTSkip("This machine has ANSI keyboard, cannot test non-ANSI rejection")
        }
    }
    
    // MARK: - All Available Layouts
    
    func testResolveLabels_allAvailableLayouts() {
        let layouts = ClipboardUtil.getAvailableInputSources()
        var results: [(layout: String, labelCount: Int, success: Bool)] = []
        
        for layout in layouts {
            let switched = ClipboardUtil.switchToInputSource(withID: layout)
            guard switched else {
                results.append((layout, 0, false))
                continue
            }
            
            let labels = provider.resolveLabels()
            let count = labels?.count ?? 0
            let ok = count == KeyboardLayoutProvider.ansiKeycodes.count
            results.append((layout, count, ok))
        }
        
        print("\n=== Keyboard Layout Provider Results ===")
        for r in results {
            let status = r.success ? "OK" : "SKIP"
            print("[\(status)] \(r.layout): \(r.labelCount) labels")
        }
        print("=========================================\n")
    }
}

@MainActor
final class AddSpaceAfterSentenceTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        AppPreferences.shared.addSpaceAfterSentence = true
    }
    
    override func tearDown() {
        AppPreferences.shared.addSpaceAfterSentence = true
        super.tearDown()
    }
    
    func testApplyPostProcessing_addsSpaceWhenEndsWithPeriod() {
        let result = IndicatorViewModel.applyPostProcessing("Hello world.")
        XCTAssertEqual(result, "Hello world. ")
    }
    
    func testApplyPostProcessing_noSpaceWhenNoPeriod() {
        let result = IndicatorViewModel.applyPostProcessing("Hello world")
        XCTAssertEqual(result, "Hello world")
    }
    
    func testApplyPostProcessing_noSpaceWhenDisabled() {
        AppPreferences.shared.addSpaceAfterSentence = false
        let result = IndicatorViewModel.applyPostProcessing("Hello world.")
        XCTAssertEqual(result, "Hello world.")
    }
    
    func testApplyPostProcessing_emptyString() {
        let result = IndicatorViewModel.applyPostProcessing("")
        XCTAssertEqual(result, "")
    }
    
    func testApplyPostProcessing_onlyPeriod() {
        let result = IndicatorViewModel.applyPostProcessing(".")
        XCTAssertEqual(result, ". ")
    }
    
    func testApplyPostProcessing_endsWithQuestionMark() {
        let result = IndicatorViewModel.applyPostProcessing("How are you?")
        XCTAssertEqual(result, "How are you? ")
    }
    
    func testApplyPostProcessing_endsWithExclamationMark() {
        let result = IndicatorViewModel.applyPostProcessing("Wow!")
        XCTAssertEqual(result, "Wow! ")
    }
    
    func testApplyPostProcessing_endsWithComma() {
        let result = IndicatorViewModel.applyPostProcessing("First,")
        XCTAssertEqual(result, "First, ")
    }
    
    func testApplyPostProcessing_endsWithColon() {
        let result = IndicatorViewModel.applyPostProcessing("Note:")
        XCTAssertEqual(result, "Note: ")
    }
    
    func testApplyPostProcessing_endsWithSemicolon() {
        let result = IndicatorViewModel.applyPostProcessing("Done;")
        XCTAssertEqual(result, "Done; ")
    }
    
    func testApplyPostProcessing_endsWithEllipsis() {
        let result = IndicatorViewModel.applyPostProcessing("Well...")
        XCTAssertEqual(result, "Well... ")
    }
    
    func testApplyPostProcessing_multipleSentences() {
        let result = IndicatorViewModel.applyPostProcessing("First sentence. Second sentence.")
        XCTAssertEqual(result, "First sentence. Second sentence. ")
    }
    
    func testApplyPostProcessing_endsWithLetterNoSpace() {
        let result = IndicatorViewModel.applyPostProcessing("No punctuation here")
        XCTAssertEqual(result, "No punctuation here")
    }
    
    func testApplyPostProcessing_defaultPreferenceIsEnabled() {
        UserDefaults.standard.removeObject(forKey: "addSpaceAfterSentence")
        let result = IndicatorViewModel.applyPostProcessing("Test.")
        XCTAssertEqual(result, "Test. ")
    }
}

final class LiveTranscriptionAccumulatorTests: XCTestCase {
    private func timedToken(
        _ text: String,
        startTime: Double,
        endTime: Double,
        id: WhisperToken = 0
    ) -> WhisperTimedToken {
        WhisperTimedToken(
            id: id,
            text: text,
            startTime: startTime,
            endTime: endTime
        )
    }

    func testApply_commitsOnlyStableSegmentsAndKeepsTailAsPreview() {
        var accumulator = LiveTranscriptionAccumulator(addSpaceAfterSentence: false)

        let update = accumulator.apply(
            segments: [
                WhisperSegmentResult(text: "hello", startTime: 0.0, endTime: 1.0),
                WhisperSegmentResult(text: "world", startTime: 1.0, endTime: 2.8),
            ],
            liveEdge: 3.5,
            isFinal: false
        )

        XCTAssertEqual(update.committedText, "hello")
        XCTAssertEqual(update.committedDelta, "hello")
        XCTAssertEqual(update.previewTail, " world")
        XCTAssertEqual(update.committedEndTime, 1.0)
        XCTAssertFalse(update.isFinal)
    }

    func testApply_skipsCommittedOverlapAndFlushesTailOnFinal() {
        var accumulator = LiveTranscriptionAccumulator(addSpaceAfterSentence: false)

        _ = accumulator.apply(
            segments: [
                WhisperSegmentResult(text: "hello", startTime: 0.0, endTime: 1.0),
                WhisperSegmentResult(text: "world", startTime: 1.0, endTime: 2.8),
            ],
            liveEdge: 3.5,
            isFinal: false
        )

        let secondUpdate = accumulator.apply(
            segments: [
                WhisperSegmentResult(text: "hello", startTime: 0.0, endTime: 1.0),
                WhisperSegmentResult(text: "world", startTime: 1.0, endTime: 2.8),
                WhisperSegmentResult(text: "again", startTime: 2.8, endTime: 4.0),
            ],
            liveEdge: 5.0,
            isFinal: false
        )

        XCTAssertEqual(secondUpdate.committedText, "hello world")
        XCTAssertEqual(secondUpdate.committedDelta, " world")
        XCTAssertEqual(secondUpdate.previewTail, " again")
        XCTAssertEqual(secondUpdate.committedEndTime, 2.8)
        XCTAssertFalse(secondUpdate.isFinal)

        let finalUpdate = accumulator.apply(
            segments: [
                WhisperSegmentResult(text: "hello", startTime: 0.0, endTime: 1.0),
                WhisperSegmentResult(text: "world", startTime: 1.0, endTime: 2.8),
                WhisperSegmentResult(text: "again", startTime: 2.8, endTime: 4.0),
            ],
            liveEdge: 5.0,
            isFinal: true
        )

        XCTAssertEqual(finalUpdate.committedText, "hello world again")
        XCTAssertEqual(finalUpdate.committedDelta, " again")
        XCTAssertEqual(finalUpdate.previewTail, "")
        XCTAssertEqual(finalUpdate.committedEndTime, 4.0)
        XCTAssertTrue(finalUpdate.isFinal)
    }

    func testApply_addSpaceAfterSentence_onlyTouchesCommittedDelta() {
        var accumulator = LiveTranscriptionAccumulator(addSpaceAfterSentence: true)

        let first = accumulator.apply(
            segments: [
                WhisperSegmentResult(text: "Hello.", startTime: 0.0, endTime: 1.0),
                WhisperSegmentResult(text: "preview?", startTime: 1.0, endTime: 2.2),
            ],
            liveEdge: 3.0,
            isFinal: false
        )

        XCTAssertEqual(first.committedDelta, "Hello. ")
        XCTAssertEqual(first.committedText, "Hello. ")
        XCTAssertEqual(first.previewTail, "preview?")

        let second = accumulator.apply(
            segments: [
                WhisperSegmentResult(text: "Hello.", startTime: 0.0, endTime: 1.0),
                WhisperSegmentResult(text: "World.", startTime: 1.0, endTime: 2.0),
            ],
            liveEdge: 3.8,
            isFinal: false
        )

        XCTAssertEqual(second.committedDelta, "World. ")
        XCTAssertEqual(second.committedText, "Hello. World. ")
        XCTAssertEqual(second.previewTail, "")
    }

    func testApply_stripsRepeatedPrefixWhenBoundaryTimestampsShift() {
        var accumulator = LiveTranscriptionAccumulator(addSpaceAfterSentence: false)

        _ = accumulator.apply(
            segments: [
                WhisperSegmentResult(text: "Okay this is a streaming test", startTime: 0.0, endTime: 2.4),
                WhisperSegmentResult(text: "let's see what happens", startTime: 2.4, endTime: 4.2),
            ],
            liveEdge: 6.0,
            isFinal: false
        )

        let update = accumulator.apply(
            segments: [
                WhisperSegmentResult(text: "Okay this is a streaming test", startTime: 0.0, endTime: 2.6),
                WhisperSegmentResult(text: "let's see what happens", startTime: 2.6, endTime: 4.6),
                WhisperSegmentResult(text: "oh yeah we can see the text updating", startTime: 4.6, endTime: 7.0),
            ],
            liveEdge: 8.8,
            isFinal: false
        )

        XCTAssertEqual(
            update.committedText,
            "Okay this is a streaming test let's see what happens oh yeah we can see the text updating"
        )
        XCTAssertEqual(update.committedDelta, " oh yeah we can see the text updating")
        XCTAssertEqual(update.previewTail, "")
    }

    func testApply_stripsRepeatedPreviewPrefixAgainstCommittedText() {
        var accumulator = LiveTranscriptionAccumulator(addSpaceAfterSentence: false)

        _ = accumulator.apply(
            segments: [
                WhisperSegmentResult(text: "that's really cool", startTime: 0.0, endTime: 2.0),
            ],
            liveEdge: 4.0,
            isFinal: false
        )

        let update = accumulator.apply(
            segments: [
                WhisperSegmentResult(text: "that's really cool", startTime: 0.0, endTime: 2.2),
                WhisperSegmentResult(text: "so yeah I think what we have to do", startTime: 2.2, endTime: 5.0),
            ],
            liveEdge: 5.8,
            isFinal: false
        )

        XCTAssertEqual(update.committedText, "that's really cool")
        XCTAssertEqual(update.committedDelta, "")
        XCTAssertEqual(update.previewTail, " so yeah I think what we have to do")
    }

    func testApply_usesTimedTokensToAvoidRecommittingMergedPrefix() {
        var accumulator = LiveTranscriptionAccumulator(addSpaceAfterSentence: false)

        _ = accumulator.apply(
            segments: [
                WhisperSegmentResult(
                    text: "Okay, so this is a test recording so I'm not repeating anything",
                    startTime: 0.0,
                    endTime: 5.28,
                    tokens: [
                        timedToken("Okay, so this", startTime: 0.0, endTime: 1.1),
                        timedToken(" is a test", startTime: 1.1, endTime: 2.2),
                        timedToken(" recording so I'm", startTime: 2.2, endTime: 3.5),
                        timedToken(" not repeating", startTime: 3.5, endTime: 4.3),
                        timedToken(" anything", startTime: 4.3, endTime: 5.28),
                    ]
                ),
            ],
            liveEdge: 8.0,
            isFinal: false
        )

        let update = accumulator.apply(
            segments: [
                WhisperSegmentResult(
                    text: "Okay, so this is a test recording so I'm not repeating anything. We can see why it is repeated",
                    startTime: 0.0,
                    endTime: 8.48,
                    tokens: [
                        timedToken("Okay, so this", startTime: 0.0, endTime: 1.2),
                        timedToken(" is a test", startTime: 1.2, endTime: 2.4),
                        timedToken(" recording so I'm", startTime: 2.4, endTime: 3.6),
                        timedToken(" not repeating", startTime: 3.6, endTime: 4.5),
                        timedToken(" anything", startTime: 4.5, endTime: 5.28),
                        timedToken(".", startTime: 5.28, endTime: 5.4),
                        timedToken(" We can", startTime: 5.4, endTime: 6.0),
                        timedToken(" see why", startTime: 6.0, endTime: 6.8),
                        timedToken(" it is", startTime: 6.8, endTime: 7.5),
                        timedToken(" repeated", startTime: 7.5, endTime: 8.48),
                    ]
                ),
            ],
            liveEdge: 10.0,
            isFinal: false
        )

        XCTAssertEqual(
            update.committedText,
            "Okay, so this is a test recording so I'm not repeating anything. We can see why it is"
        )
        XCTAssertEqual(update.committedDelta, " anything. We can see why it is")
        XCTAssertEqual(update.previewTail, " repeated")
        XCTAssertEqual(update.committedEndTime, 7.5)
    }

    func testApply_stripsWhisperControlTokensAndSilenceHallucinationPhrases() {
        var accumulator = LiveTranscriptionAccumulator(addSpaceAfterSentence: false)

        let update = accumulator.apply(
            segments: [
                WhisperSegmentResult(
                    text: "[_BEG_] Ask for follow up changes [_TT_191] I'm talking right now",
                    startTime: 0.0,
                    endTime: 3.0
                ),
            ],
            liveEdge: 4.8,
            isFinal: false
        )

        XCTAssertEqual(update.committedText, "I'm talking right now")
        XCTAssertEqual(update.committedDelta, "I'm talking right now")
        XCTAssertEqual(update.previewTail, "")
    }

    func testApply_stripsOnlyTrailingStandaloneFollowUpHallucination() {
        var accumulator = LiveTranscriptionAccumulator(addSpaceAfterSentence: false)

        let update = accumulator.apply(
            segments: [
                WhisperSegmentResult(
                    text: "However, there's the ask for follow-up changes being appended at the end. Ask for follow-up changes",
                    startTime: 0.0,
                    endTime: 4.0
                ),
            ],
            liveEdge: 6.0,
            isFinal: false
        )

        XCTAssertEqual(
            update.committedText,
            "However, there's the ask for follow-up changes being appended at the end."
        )
        XCTAssertEqual(
            update.committedDelta,
            "However, there's the ask for follow-up changes being appended at the end."
        )
        XCTAssertEqual(update.previewTail, "")
    }

    func testApply_stripsTrailingStandaloneHallucinationFragmentAcrossChunkBoundaries() {
        var accumulator = LiveTranscriptionAccumulator(addSpaceAfterSentence: false)

        let firstUpdate = accumulator.apply(
            segments: [
                WhisperSegmentResult(
                    text: "However, there's the ask for follow-up changes being appended at the end. Ask for",
                    startTime: 0.0,
                    endTime: 4.0
                ),
            ],
            liveEdge: 6.0,
            isFinal: false
        )

        XCTAssertEqual(
            firstUpdate.committedText,
            "However, there's the ask for follow-up changes being appended at the end."
        )
        XCTAssertEqual(
            firstUpdate.committedDelta,
            "However, there's the ask for follow-up changes being appended at the end."
        )
        XCTAssertEqual(firstUpdate.previewTail, "")

        let secondUpdate = accumulator.apply(
            segments: [
                WhisperSegmentResult(
                    text: "However, there's the ask for follow-up changes being appended at the end. Ask for follow-up changes",
                    startTime: 0.0,
                    endTime: 5.0
                ),
            ],
            liveEdge: 7.0,
            isFinal: false
        )

        XCTAssertEqual(
            secondUpdate.committedText,
            "However, there's the ask for follow-up changes being appended at the end."
        )
        XCTAssertEqual(secondUpdate.committedDelta, "")
        XCTAssertEqual(secondUpdate.previewTail, "")
    }

    func testApply_defersTrailingPartialTokenUntilWordBoundaryArrives() {
        var accumulator = LiveTranscriptionAccumulator(addSpaceAfterSentence: false)

        let firstUpdate = accumulator.apply(
            segments: [
                WhisperSegmentResult(
                    text: "halluc",
                    startTime: 0.0,
                    endTime: 1.6,
                    tokens: [
                        timedToken(" halluc", startTime: 0.0, endTime: 1.6),
                    ]
                ),
            ],
            liveEdge: 3.5,
            isFinal: false
        )

        XCTAssertEqual(firstUpdate.committedText, "")
        XCTAssertEqual(firstUpdate.committedDelta, "")
        XCTAssertEqual(firstUpdate.previewTail, "halluc")

        let secondUpdate = accumulator.apply(
            segments: [
                WhisperSegmentResult(
                    text: "hallucinations for repetitions",
                    startTime: 0.0,
                    endTime: 4.5,
                    tokens: [
                        timedToken(" halluc", startTime: 0.0, endTime: 1.6),
                        timedToken("inations", startTime: 1.6, endTime: 2.3),
                        timedToken(" for", startTime: 2.3, endTime: 3.0),
                        timedToken(" repetitions", startTime: 3.0, endTime: 4.5),
                    ]
                ),
            ],
            liveEdge: 5.8,
            isFinal: false
        )

        XCTAssertEqual(secondUpdate.committedText, "hallucinations")
        XCTAssertEqual(secondUpdate.committedDelta, "hallucinations")
        XCTAssertEqual(secondUpdate.previewTail, " for repetitions")
    }

    func testApply_tokenPathStripsSingleWordBoundaryOverlap() {
        var accumulator = LiveTranscriptionAccumulator(addSpaceAfterSentence: false)

        _ = accumulator.apply(
            segments: [
                WhisperSegmentResult(
                    text: "I'm just",
                    startTime: 0.0,
                    endTime: 2.0,
                    tokens: [
                        timedToken(" I'm", startTime: 0.0, endTime: 1.0),
                        timedToken(" just", startTime: 1.0, endTime: 2.0),
                        timedToken(" speaking", startTime: 2.0, endTime: 3.0),
                    ]
                ),
            ],
            liveEdge: 3.2,
            isFinal: false
        )

        let update = accumulator.apply(
            segments: [
                WhisperSegmentResult(
                    text: "just speaking and hopefully",
                    startTime: 1.7,
                    endTime: 5.0,
                    tokens: [
                        timedToken(" just", startTime: 1.7, endTime: 2.3),
                        timedToken(" speaking", startTime: 2.3, endTime: 3.2),
                        timedToken(" and", startTime: 3.2, endTime: 4.0),
                        timedToken(" hopefully", startTime: 4.0, endTime: 5.0),
                    ]
                ),
            ],
            liveEdge: 6.8,
            isFinal: false
        )

        XCTAssertEqual(update.committedText, "just speaking and")
        XCTAssertEqual(update.committedDelta, "just speaking and")
        XCTAssertEqual(update.previewTail, " hopefully")
    }
}

final class BufferedTextInsertionStateTests: XCTestCase {

    func testRecordCommittedDelta_buffersWhenLiveInsertionFailsAndFinalizesOnce() {
        var state = BufferedTextInsertionState(liveInsertionEnabled: true)

        state.recordCommittedDelta("hello", insertedLive: true)
        XCTAssertTrue(state.liveInsertionEnabled)
        XCTAssertEqual(state.bufferedText, "")

        state.recordCommittedDelta(" world", insertedLive: false)
        XCTAssertFalse(state.liveInsertionEnabled)
        XCTAssertEqual(state.bufferedText, " world")

        state.recordCommittedDelta("!", insertedLive: true)
        XCTAssertEqual(state.bufferedText, " world!")

        let finalized = state.finalizeBufferedText()
        XCTAssertEqual(finalized, " world!")
        XCTAssertEqual(state.bufferedText, "")
        XCTAssertNil(state.finalizeBufferedText())
    }

    func testRecordCommittedDelta_noopForEmptyText() {
        var state = BufferedTextInsertionState(liveInsertionEnabled: false)

        state.recordCommittedDelta("", insertedLive: false)

        XCTAssertFalse(state.liveInsertionEnabled)
        XCTAssertEqual(state.bufferedText, "")
        XCTAssertNil(state.finalizeBufferedText())
    }
}

final class LiveTranscriptPreviewFormattingTests: XCTestCase {
    func testCombineLivePreviewText_insertsSingleBoundarySpaceBetweenCommittedAndPreview() {
        let combined = TranscriptionService.combineLivePreviewText(
            committedText: "I'm testing to see if",
            previewText: "the follow-up changes line appears"
        )

        XCTAssertEqual(combined, "I'm testing to see if the follow-up changes line appears")
    }

    func testCombineLivePreviewText_avoidsExtraSpaceBeforePunctuation() {
        let combined = TranscriptionService.combineLivePreviewText(
            committedText: "Hello",
            previewText: ", world"
        )

        XCTAssertEqual(combined, "Hello, world")
    }
}

@MainActor
final class FocusedTextInsertionSessionTests: XCTestCase {
    private final class StringCaptureBox: @unchecked Sendable {
        var value: String?
    }

    func testAppendCommittedDelta_reusesLastInsertedRangeForLaterWrites() {
        let snapshot = FocusedTextTargetSnapshot(
            frontmostApplicationPID: 1,
            element: AXUIElementCreateSystemWide(),
            selectedTextRange: CFRange(location: 12, length: 0)
        )
        var observedRanges: [CFRange?] = []
        var returnedRanges = [
            CFRange(location: 17, length: 0),
            CFRange(location: 23, length: 0),
        ]

        let session = FocusedTextInsertionSession(
            snapshot: snapshot,
            releaseInserter: { _ in XCTFail("Release insertion should not be used during successful live writes") },
            liveInserter: { _, _, preferredRange in
                observedRanges.append(preferredRange)
                return returnedRanges.removeFirst()
            }
        )

        session.appendCommittedDelta("hello")
        session.appendCommittedDelta(" world")

        XCTAssertEqual(observedRanges.count, 2)
        XCTAssertEqual(observedRanges[0]?.location, 12)
        XCTAssertEqual(observedRanges[1]?.location, 17)
    }

    func testFinalizeReleaseInsertion_stripsTrailingStandaloneHallucinationFragment() {
        let insertedText = StringCaptureBox()

        let session = FocusedTextInsertionSession(
            snapshot: nil,
            releaseInserter: { insertedText.value = $0 },
            liveInserter: { _, _, _ in
                XCTFail("Live inserter should not be used when snapshot is unavailable")
                return nil
            }
        )

        session.appendCommittedDelta(
            "However, there's the ask for follow-up changes being appended at the end. Ask for"
        )
        session.appendCommittedDelta(" follow-up changes")

        let finalizedText = session.finalizeReleaseInsertion()

        XCTAssertEqual(
            finalizedText,
            "However, there's the ask for follow-up changes being appended at the end."
        )
        XCTAssertEqual(
            insertedText.value,
            "However, there's the ask for follow-up changes being appended at the end."
        )
    }
}
