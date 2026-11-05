import XCTest

final class NotaryLedgerSmokeTests: XCTestCase {
    @MainActor private func launch(_ link: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--auth-fixtures"]
        if let link { app.launchArguments.append("--auth-url=\(link)") }
        app.launch()
        return app
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }
    @MainActor private func enter(_ value: String, into field: XCUIElement, in app: XCUIApplication) {
        reveal(field, in: app)
        field.tap()
        field.typeText(value)
    }
    @MainActor private func fillSignup(_ app: XCUIApplication, email: String = "avery@example.test") {
        enter("Avery", into: app.textFields["First name"], in: app)
        enter("Notary", into: app.textFields["Last name"], in: app)
        enter(email, into: app.textFields["Email"], in: app)
        enter("StrongPass12!", into: app.secureTextFields["Password"], in: app)
        app.buttons["Show password"].tap()
        XCTAssertEqual(app.textFields["Password"].value as? String, "StrongPass12!")
        enter("StrongPass12!", into: app.secureTextFields["Confirm password"], in: app)
        app.buttons["Show confirm password"].tap()
        XCTAssertEqual(app.textFields["Confirm password"].value as? String, "StrongPass12!")
        reveal(app.buttons["Create Account"], in: app)
        app.buttons["Create Account"].tap()
    }

    @MainActor func testLoginValidationAndRecoveryNavigation() throws {
        let app = launch()
        let login = app.buttons["Log In"]
        XCTAssertTrue(login.waitForExistence(timeout: 10))
        login.tap()
        XCTAssertTrue(app.staticTexts["Please enter your email."].waitForExistence(timeout: 5))
        app.buttons["Forgot password"].tap()
        XCTAssertTrue(app.buttons["Send Reset Link"].waitForExistence(timeout: 5))
        enter("avery@example.test", into: app.textFields["Email"], in: app)
        reveal(app.buttons["Send Reset Link"], in: app)
        app.buttons["Send Reset Link"].tap()
        XCTAssertTrue(app.staticTexts["If an account exists for that email, a password reset link has been sent."].waitForExistence(timeout: 5))
        app.buttons["Back to sign in"].tap()
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["If an account exists for that email, a password reset link has been sent."].exists)
    }

    @MainActor func testSignupVerificationReturnsToLoginWithEmailAndMessage() throws {
        let app = launch("https://notaryledger.org/signup")
        XCTAssertTrue(app.staticTexts["Set up your desk"].waitForExistence(timeout: 10))
        fillSignup(app)
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Check your email to verify your account, then sign in."].exists)
        XCTAssertEqual(app.textFields["Email"].value as? String, "avery@example.test")
        app.buttons["Log In"].tap()
        XCTAssertTrue(app.staticTexts["Please enter your password."].waitForExistence(timeout: 5))
    }

    @MainActor func testDuplicateSignupRemainsOnSignupWithWebError() throws {
        let app = launch("https://notaryledger.org/signup")
        XCTAssertTrue(app.staticTexts["Set up your desk"].waitForExistence(timeout: 10))
        fillSignup(app, email: "exists@example.test")
        let error = app.staticTexts["An account with this email already exists. Please sign in or use a different email address."]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Set up your desk"].exists)
    }

    @MainActor func testLoginFailureThenSuccessHonorsBillingDestination() throws {
        let app = launch("https://notaryledger.org/login?next=billing")
        XCTAssertTrue(app.buttons["Log In"].waitForExistence(timeout: 10))
        enter("avery@example.test", into: app.textFields["Email"], in: app)
        enter("WrongPassword1!", into: app.secureTextFields["Password"], in: app)
        reveal(app.buttons["Log In"], in: app)
        app.buttons["Log In"].tap()
        XCTAssertTrue(app.staticTexts["Invalid email or password."].waitForExistence(timeout: 5))
        let field = app.secureTextFields["Password"]
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "WrongPassword1!".count) + "StrongPass12!")
        reveal(app.buttons["Log In"], in: app)
        app.buttons["Log In"].tap()
        XCTAssertTrue(app.staticTexts["Billing"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Welcome back"].exists)
    }

    @MainActor func testPasswordResetReturnsToLoginWithConfirmation() throws {
        let app = launch("https://notaryledger.org/reset-password?token=valid")
        XCTAssertTrue(app.staticTexts["Reset your password"].waitForExistence(timeout: 10))
        enter("StrongPass12!", into: app.secureTextFields["New password"], in: app)
        enter("StrongPass12!", into: app.secureTextFields["Confirm new password"], in: app)
        reveal(app.buttons["Reset Password"], in: app)
        app.buttons["Reset Password"].tap()
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your password has been reset. Sign in with your new password."].exists)
    }

    @MainActor func testVerificationSuccessAndExpiredLinkHaveCorrectActions() throws {
        let verified = launch("https://notaryledger.org/verify-email?token=valid")
        XCTAssertTrue(verified.staticTexts["Email verified successfully"].waitForExistence(timeout: 10))
        XCTAssertFalse(verified.buttons["Create account"].exists)
        verified.buttons["Go to sign in"].tap()
        XCTAssertTrue(verified.staticTexts["Welcome back"].waitForExistence(timeout: 5))
        verified.terminate()
        let expired = launch("https://notaryledger.org/verify-email?token=expired")
        XCTAssertTrue(expired.staticTexts["This verification link is invalid or expired."].waitForExistence(timeout: 10))
        expired.buttons["Create account"].tap()
        XCTAssertTrue(expired.staticTexts["Set up your desk"].waitForExistence(timeout: 5))
    }
}
