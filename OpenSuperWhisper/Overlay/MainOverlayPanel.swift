import AppKit

final class MainOverlayPanel: NSPanel {
    var resignHandler: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func resignKey() {
        super.resignKey()
        resignHandler?()
    }
}
