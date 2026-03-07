import XCTest
@testable import OpenSuperWhisper

final class ShortcutManagerTests: XCTestCase {
    func testHoldToRecordStopsOnReleaseWithoutHandsFree() {
        var state = ShortcutRecordingInteractionState()

        XCTAssertEqual(state.handleHotkeyDown(holdToRecordEnabled: true), .start)
        state.enableHoldModeIfNeeded()

        XCTAssertEqual(state.handleHotkeyUp(holdToRecordEnabled: true), .stop)
        XCTAssertFalse(state.isSessionActive)
        XCTAssertFalse(state.handsFreeMode)
    }

    func testCommandWhileHoldingLatchesHandsFreeUntilNextPress() {
        var state = ShortcutRecordingInteractionState()

        XCTAssertEqual(state.handleHotkeyDown(holdToRecordEnabled: true), .start)
        XCTAssertTrue(
            state.handleCommandDown(
                holdToRecordEnabled: true,
                supportsHandsFreeActivation: true
            )
        )
        XCTAssertTrue(state.handsFreeMode)

        XCTAssertEqual(state.handleHotkeyUp(holdToRecordEnabled: true), .none)
        XCTAssertTrue(state.isSessionActive)

        XCTAssertEqual(state.handleHotkeyDown(holdToRecordEnabled: true), .stop)
        XCTAssertFalse(state.isSessionActive)
    }

    func testCommandDoesNotLatchWhenModifierOnlyHotkeyIsCommand() {
        var state = ShortcutRecordingInteractionState()

        XCTAssertEqual(state.handleHotkeyDown(holdToRecordEnabled: true), .start)
        XCTAssertFalse(
            state.handleCommandDown(
                holdToRecordEnabled: true,
                supportsHandsFreeActivation: false
            )
        )
        XCTAssertFalse(state.handsFreeMode)
    }

    func testTapToToggleStillStopsOnSecondPressWhenHoldToRecordIsDisabled() {
        var state = ShortcutRecordingInteractionState()

        XCTAssertEqual(state.handleHotkeyDown(holdToRecordEnabled: false), .start)
        XCTAssertEqual(state.handleHotkeyUp(holdToRecordEnabled: false), .none)
        XCTAssertEqual(state.handleHotkeyDown(holdToRecordEnabled: false), .stop)
        XCTAssertFalse(state.isSessionActive)
    }
}
