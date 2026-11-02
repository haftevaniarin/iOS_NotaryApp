import XCTest

final class NotaryLedgerSmokeTests: XCTestCase {
    @MainActor
    func testLoginValidationAndRecoveryNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        let login = app.buttons["Log In"]
        XCTAssertTrue(login.waitForExistence(timeout: 15))
        login.tap()
        XCTAssertTrue(app.staticTexts["Enter your email address."].waitForExistence(timeout: 5))
        app.buttons["Forgot password"].tap()
        XCTAssertTrue(app.buttons["Send Reset Link"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Notary Ledger recovery screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
