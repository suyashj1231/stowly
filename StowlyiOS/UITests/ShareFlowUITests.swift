import XCTest

/// End to end on a simulator: pair through the `stowly://pair` link (what scanning the Mac's QR
/// with the Camera app does), then Safari → Share → Stowly and wait for the confirmation.
///
/// Run with a relay topic you control, and something acking it in place of the Mac:
///   TEST_RUNNER_STOWLY_TOPIC=stowly-test123 xcodebuild test -scheme StowlyiOS -destination …
@MainActor
final class ShareFlowUITests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testPairThenShareFromSafari() throws {
        let topic = try XCTUnwrap(ProcessInfo.processInfo.environment["STOWLY_TOPIC"], "set TEST_RUNNER_STOWLY_TOPIC")

        // Pair.
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.system.open(URL(string: "stowly://pair?topic=\(topic)")!)
        let open = springboard.buttons["Open"]
        if open.waitForExistence(timeout: 5) { open.tap() }
        XCTAssertTrue(app.navigationBars["Stowly"].waitForExistence(timeout: 10), "paired: the sent list is showing")
        snapshot("paired")

        // Share a YouTube page from Safari (a static one, so the test isn't waiting on autoplay).
        XCUIDevice.shared.system.open(URL(string: "https://www.youtube.com/t/terms")!)
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 10))
        let share = safari.buttons["ShareButton"].firstMatch
        if !share.waitForExistence(timeout: 8) {
            // iOS 26 Safari keeps Share in the "•••" menu.
            let more = safari.buttons.matching(NSPredicate(format: "label IN %@", ["More", "Page Menu", "Tab Menu"])).firstMatch
            if !more.waitForExistence(timeout: 5) { print(safari.debugDescription) }
            more.tap()
        }
        let shareItem = share.exists ? share : safari.buttons["Share"].firstMatch
        if !shareItem.waitForExistence(timeout: 5) { print(safari.debugDescription) }
        shareItem.tap()

        let stowly = safari.cells["Stowly"].firstMatch
        if !stowly.waitForExistence(timeout: 8) { print(safari.debugDescription) }
        XCTAssertTrue(stowly.exists, "Stowly in the share sheet")
        stowly.tap()

        let delivered = safari.staticTexts["On your Mac"].firstMatch
        XCTAssertTrue(delivered.waitForExistence(timeout: 10), "share sheet confirms delivery")
        snapshot("delivered")

        // The app lists it as delivered.
        app.activate()
        XCTAssertTrue(app.staticTexts["YouTube"].waitForExistence(timeout: 10), "post listed")
        snapshot("list")
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
