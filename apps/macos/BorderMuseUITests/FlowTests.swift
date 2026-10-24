import AppKit
import CoreGraphics
import ImageIO
import XCTest

@MainActor
final class FlowTests: XCTestCase {
    var app: XCUIApplication!
    var root: URL!
    var input: URL!
    var output: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        root = FileManager.default.temporaryDirectory.appendingPathComponent("bordermuse-ui-\(UUID())")
        input = root.appendingPathComponent("input")
        output = root.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        app = XCUIApplication()
        app.launchEnvironment["BORDERMUSE_UI_TEST_SESSION"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["addPhotosToolbar"].waitForExistence(timeout: 15))
    }
    override func tearDownWithError() throws {
        let screenshot = XCTAttachment(screenshot: app.windows["main"].screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate()
        try? FileManager.default.removeItem(at: root)
    }
    @discardableResult
    func fixture(_ name: String, width: Int = 1000, height: Int = 800) throws -> URL {
        let url = input.appendingPathComponent(name)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.65, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.8, green: 0.35, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
    func wait(_ condition: @escaping () -> Bool, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, app.debugDescription, file: file, line: line)
    }
    func goTo(_ path: URL) {
        app.typeKey("g", modifierFlags: [.command, .shift])
        let field = app.textFields["PathTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.click(); field.typeKey("a", modifierFlags: .command); field.typeText(path.path)
        app.typeKey(.return, modifierFlags: [])
    }
    func importPhoto(_ file: URL) {
        app.buttons["addPhotosToolbar"].click()
        XCTAssertTrue(app.dialogs.firstMatch.waitForExistence(timeout: 5))
        goTo(file)
        // The application also exposes a Touch Bar button named Open. Limit the
        // query to the visible panel so XCTest never targets its virtual copy.
        let open = app.dialogs.firstMatch.buttons["Open"].firstMatch
        if open.waitForExistence(timeout: 3) { open.click() }
        XCTAssertTrue(app.buttons["photo-\(file.lastPathComponent)"].waitForExistence(timeout: 10), app.debugDescription)
        wait { self.app.buttons["exportButton"].isEnabled }
    }
    func exportPhotos() {
        app.buttons["exportButton"].click()
        chooseExportFolder()
    }
    func chooseExportFolder() {
        XCTAssertTrue(app.dialogs.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        goTo(output)
        let choose = app.dialogs.firstMatch.buttons["Export Here"].firstMatch
        XCTAssertTrue(choose.waitForExistence(timeout: 5), app.debugDescription)
        choose.click()
        XCTAssertTrue(app.staticTexts["exportStatus"].waitForExistence(timeout: 20), app.debugDescription)
    }
    func testImportAdjustExportAndRevealWithoutOverwriting() throws {
        let photo = try fixture("landscape.png")
        let original = try Data(contentsOf: photo)
        importPhoto(photo)
        app.popUpButtons["ratioPicker"].click()
        app.menuItems["1:1"].click()
        wait {
            let preview = self.app.descendants(matching: .any).matching(identifier: "exportPreview").firstMatch
            return preview.label == "Preview of landscape.png. Output: 1,100 × 1,100 px"
        }
        exportPhotos()
        let exported = output.appendingPathComponent("landscape-border.png")
        wait { FileManager.default.fileExists(atPath: exported.path) }
        let source = CGImageSourceCreateWithURL(exported as CFURL, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        XCTAssertEqual(image.width, 1100); XCTAssertEqual(image.height, 1100)
        let firstBytes = try Data(contentsOf: exported)
        exportPhotos()
        wait { FileManager.default.fileExists(atPath: self.output.appendingPathComponent("landscape-border-2.png").path) }
        XCTAssertEqual(try Data(contentsOf: exported), firstBytes)
        XCTAssertEqual(try Data(contentsOf: photo), original)
        app.links["showFinder"].click()
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        let folder = finder.windows[output.lastPathComponent]
        wait { folder.exists }
        wait { folder.descendants(matching: .any).matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "landscape-border-2", "landscape-border-2")).firstMatch.exists }
        app.activate()
    }
    func testInvalidTextDisablesExportAndArrowKeysSelectPhotos() throws {
        importPhoto(try fixture("first.png"))
        importPhoto(try fixture("second.png", width: 800, height: 1200))
        let field = app.textFields["thicknessField"]
        field.click(); field.typeKey("a", modifierFlags: .command); field.typeText("abc")
        wait { !self.app.buttons["exportButton"].isEnabled }
        // A custom accessibility label groups the error's text and icon.
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "settingsError").firstMatch.exists)
        field.typeKey("a", modifierFlags: .command); field.typeText("20")
        wait { self.app.buttons["exportButton"].isEnabled }
        app.buttons["photo-first.png"].click()
        app.typeKey(.rightArrow, modifierFlags: [])
        wait { self.app.buttons["photo-second.png"].isSelected }
        app.typeKey(.delete, modifierFlags: [])
        wait { !self.app.buttons["photo-second.png"].exists }
    }
    func testPresetPersistsAcrossRelaunch() throws {
        importPhoto(try fixture("portrait.png", width: 800, height: 1200))
        app.popUpButtons["ratioPicker"].click(); app.menuItems["4:5"].click()
        let thickness = app.textFields["thicknessField"]
        thickness.click(); thickness.typeKey("a", modifierFlags: .command); thickness.typeText("20"); thickness.typeKey(.return, modifierFlags: [])
        app.buttons["savePreset"].click()
        let name = app.textFields["presetName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.click(); name.typeText("UI Portrait")
        app.buttons["Save"].click()
        wait { self.app.popUpButtons["presetPicker"].value as? String == "UI Portrait" }
        app.terminate(); app.launch()
        XCTAssertTrue(app.popUpButtons["presetPicker"].waitForExistence(timeout: 10))
        app.popUpButtons["presetPicker"].click(); app.menuItems["UI Portrait"].click()
        XCTAssertEqual(app.popUpButtons["ratioPicker"].value as? String, "4:5")
        XCTAssertEqual(app.textFields["thicknessField"].value as? String, "20")
        app.menuButtons["presetActions"].click(); app.menuItems["Delete Preset"].click()
        wait { self.app.popUpButtons["presetPicker"].value as? String == "Custom" }
    }
    func testMissingInputCanBeRetriedAfterRepair() throws {
        let photo = try fixture("repair.png")
        let data = try Data(contentsOf: photo)
        importPhoto(photo)
        try FileManager.default.removeItem(at: photo)
        exportPhotos()
        XCTAssertTrue(app.links["reviewIssues"].waitForExistence(timeout: 5))
        app.links["reviewIssues"].click()
        XCTAssertTrue(app.buttons["retryFailed"].waitForExistence(timeout: 5))
        try data.write(to: photo)
        app.buttons["retryFailed"].click()
        chooseExportFolder()
        wait { FileManager.default.fileExists(atPath: self.output.appendingPathComponent("repair-border.png").path) }
        XCTAssertFalse(app.links["reviewIssues"].exists)
    }
}
