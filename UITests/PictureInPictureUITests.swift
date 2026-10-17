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

    /// Swipes up from the bottom edge, as a viewer goes home (a simulated Home
    /// button press doesn't start Picture in Picture).
    private func goHome(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.998))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        start.press(forDuration: 0.02, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
