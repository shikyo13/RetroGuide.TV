import XCTest

/// Drives the app on a device one short script at a time, for checks that
/// need a person's eyes between steps. The script comes from the `STEPS`
/// environment variable (pass `TEST_RUNNER_STEPS` to xcodebuild), separated
/// by `;`:
///   launch | activate | wait:<seconds> | shot:<name> | tree
///   tap:<label> (first button, cell or text with that label)
///   tapat:<x>,<y> (normalized screen position)
///   swipe:up|down|left|right
///   slider:<label>=<position 0…1>
///   drag:<x1>,<y1>,<x2>,<y2> (normalized screen positions)
@MainActor
final class StepDriverUITests: XCTestCase {
    private let app = XCUIApplication()

    func testSteps() throws {
        let script = try XCTUnwrap(ProcessInfo.processInfo.environment["STEPS"], "set TEST_RUNNER_STEPS")
        for step in script.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) where !step.isEmpty {
            let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
            let argument = parts.count > 1 ? parts[1] : ""
            switch parts[0] {
            case "launch": app.launch()
            case "activate": app.activate()
            case "wait": Thread.sleep(forTimeInterval: Double(argument) ?? 1)
            case "shot": attachScreenshot(named: argument)
            case "tree": attach(app.debugDescription, named: "tree")
            case "tap": try tap(label: argument)
            case "tapat": tap(at: argument)
            case "swipe": swipe(argument)
            case "slider": try adjustSlider(argument)
            case "drag": drag(argument)
            default: XCTFail("unknown step \(step)")
            }
        }
    }

    private func tap(label: String) throws {
        let queries = [app.buttons, app.cells, app.staticTexts, app.otherElements]
        for query in queries {
            let element = query[label].firstMatch
            if element.waitForExistence(timeout: 2), element.isHittable {
                element.tap()
                return
            }
        }
        attach(app.debugDescription, named: "tree-missing-\(label)")
        XCTFail("no hittable element labelled \(label)")
    }

    private func tap(at argument: String) {
        let values = argument.split(separator: ",").compactMap { Double($0) }
        guard values.count == 2 else { return XCTFail("tapat needs x,y") }
        app.coordinate(withNormalizedOffset: CGVector(dx: values[0], dy: values[1])).tap()
    }

    private func adjustSlider(_ argument: String) throws {
        let parts = argument.split(separator: "=").map(String.init)
        let position = try XCTUnwrap(parts.count == 2 ? Double(parts[1]) : nil, "slider needs label=position")
        let slider = app.sliders[parts[0]].firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 2), "no slider labelled \(parts[0])")
        slider.adjust(toNormalizedSliderPosition: CGFloat(position))
    }

    private func drag(_ argument: String) {
        let values = argument.split(separator: ",").compactMap { Double($0) }
        guard values.count == 4 else { return XCTFail("drag needs x1,y1,x2,y2") }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: values[0], dy: values[1]))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: values[2], dy: values[3]))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    private func swipe(_ direction: String) {
        switch direction {
        case "up": app.swipeUp()
        case "down": app.swipeDown()
        case "left": app.swipeLeft()
        default: app.swipeRight()
        }
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attach(_ text: String, named name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
