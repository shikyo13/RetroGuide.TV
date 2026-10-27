import XCTest

/// Drives a connected iPhone through Picture in Picture: launches the app
/// (already signed in), waits for a channel, goes to the home screen and
/// takes full-screen screenshots of the floating window, then returns.
final class PictureInPictureUITests: XCTestCase {
    private enum Timing {
        static let channelStart: TimeInterval = 15
        static let pictureInPictureStart: TimeInterval = 3
        static let screenshotInterval: TimeInterval = 4
        static let screenshots = 4
        static let afterReturn: TimeInterval = 6
    }

    func testPictureInPictureOnHome() {
        let app = XCUIApplication()
        app.launch()
        Thread.sleep(forTimeInterval: Timing.channelStart)
        // A tap on the video first, as a viewer would.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: Timing.pictureInPictureStart)
        attachScreenshot(named: "1-playing")
        goHome(app)
        Thread.sleep(forTimeInterval: Timing.pictureInPictureStart)
        attachScreenshot(named: "2-first-home")
        app.activate()
        Thread.sleep(forTimeInterval: Timing.afterReturn)
        attachScreenshot(named: "3-back")
        goHome(app)
        Thread.sleep(forTimeInterval: Timing.pictureInPictureStart)
        for index in 1...Timing.screenshots {
            attachScreenshot(named: "4-second-home-\(index)")
            Thread.sleep(forTimeInterval: Timing.screenshotInterval)
        }
        app.activate()
        Thread.sleep(forTimeInterval: Timing.afterReturn)
        attachScreenshot(named: "5-back")
    }

    /// Closes the window with its X while away, comes back, and leaves
    /// again: the window should open the second time too.
    func testPictureInPictureAfterClosing() {
        let app = XCUIApplication()
        app.launch()
        Thread.sleep(forTimeInterval: Timing.channelStart)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: Timing.pictureInPictureStart)
        goHome(app)
        Thread.sleep(forTimeInterval: Timing.pictureInPictureStart)
        attachScreenshot(named: "1-home")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let window = springboard.windows["PIP-SBInteractionPassThroughView"]
        XCTAssertTrue(window.waitForExistence(timeout: Timing.pictureInPictureStart), "no window the first time")
        // Its controls show on a tap; the X is in the top-left corner.
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 0.5)
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.09, dy: 0.15)).tap()
        Thread.sleep(forTimeInterval: Timing.pictureInPictureStart)
        attachScreenshot(named: "2-closed")
        app.activate()
        Thread.sleep(forTimeInterval: Timing.channelStart)
        attachScreenshot(named: "3-back")
        goHome(app)
        Thread.sleep(forTimeInterval: Timing.pictureInPictureStart)
        attachScreenshot(named: "4-home-again")
        XCTAssertTrue(window.exists, "no window after closing it and coming back")
        app.activate()
    }

    /// Long-presses app icons on the home screen to compare their menus.
    func testIconMenus() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let app = XCUIApplication()
        app.launch()
        goHome(app)
        Thread.sleep(forTimeInterval: Timing.pictureInPictureStart)
        // Where the icons sit on the iPad's last page, in points.
        for (name, point) in [("RetroGuide.TV", CGVector(dx: 285, dy: 953)), ("Music", CGVector(dx: 681, dy: 629))] {
            springboard.coordinate(withNormalizedOffset: .zero).withOffset(point).press(forDuration: 1.2)
            Thread.sleep(forTimeInterval: 1)
            attachScreenshot(named: "menu-\(name)")
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
            Thread.sleep(forTimeInterval: 1)
        }
    }

    /// Swipes up from the bottom edge, as a viewer goes home (a simulated Home
    /// button press doesn't start Picture in Picture).
    private func goHome(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.998))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        start.press(forDuration: 0.01, thenDragTo: end, withVelocity: 4_000, thenHoldForDuration: 0)
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
