import XCTest

final class NotaryLedgerSmokeTests: XCTestCase {
    @MainActor private func launch(_ link: String? = nil, freePlan: Bool = false, customerInvoices: Bool = false, cancelRefresh: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--auth-fixtures"]
        if freePlan { app.launchArguments.append("--billing-free") }
        if customerInvoices { app.launchArguments.append("--customer-invoice-fixtures") }
        if cancelRefresh { app.launchArguments.append("--cancel-dashboard-refresh") }
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

    @MainActor func testCancelledDashboardRefreshKeepsDataAndPlanWithoutAnErrorBanner() throws {
        let app = launch(customerInvoices: true, cancelRefresh: true)
        XCTAssertTrue(app.buttons["Log In"].waitForExistence(timeout: 10))
        enter("avery@example.test", into: app.textFields["Email"], in: app)
        enter("StrongPass12!", into: app.secureTextFields["Password"], in: app)
        reveal(app.buttons["Log In"], in: app)
        app.buttons["Log In"].tap()
        let plan = app.staticTexts["Dashboard plan"]
        XCTAssertTrue(plan.waitForExistence(timeout: 10))
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Current plan: Pro"), object: plan)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 5), .completed)
        for _ in 0..<2 {
            // The fixture cancels the first pull; the next pull succeeds.
            app.scrollViews.firstMatch.swipeDown()
            XCTAssertFalse(app.staticTexts["Dashboard refresh error"].waitForExistence(timeout: 2))
            XCTAssertEqual(plan.label, "Current plan: Pro")
            XCTAssertTrue(app.staticTexts["Harbor Title"].firstMatch.exists)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Dashboard after cancelled refresh and retry"
        screenshot.lifetime = .keepAlways
        add(screenshot)
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

    @MainActor private func openNewOrder(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Log In"].waitForExistence(timeout: 10))
        enter("avery@example.test", into: app.textFields["Email"], in: app)
        enter("StrongPass12!", into: app.secureTextFields["Password"], in: app)
        reveal(app.buttons["Log In"], in: app)
        app.buttons["Log In"].tap()
        XCTAssertTrue(app.staticTexts["Dashboard plan"].waitForExistence(timeout: 10))
        app.buttons["Open navigation menu"].tap()
        app.buttons["Signings"].tap()
        app.buttons["New Signing"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
    }

    @MainActor private func enterOrderField(_ value: String, into field: XCUIElement, in app: XCUIApplication) {
        // Keep the control between the modal navigation bar and keyboard.
        // isHittable alone can include a field obscured by the navigation bar.
        for _ in 0..<12 {
            let top = app.navigationBars.firstMatch.frame.maxY + 24
            let keyboard = app.keyboards.firstMatch
            let bottom = keyboard.exists ? keyboard.frame.minY - 24 : app.frame.maxY - 70
            if field.isHittable && field.frame.midY > top && field.frame.midY < bottom { break }
            let center = app.coordinate(withNormalizedOffset: .zero)
            let upper = center.withOffset(CGVector(dx: app.frame.midX, dy: top + 20))
            let lower = center.withOffset(CGVector(dx: app.frame.midX, dy: bottom - 20))
            if field.frame.midY <= top { upper.press(forDuration: 0.05, thenDragTo: lower) }
            else { lower.press(forDuration: 0.05, thenDragTo: upper) }
        }
        field.tap()
        field.typeText(value)
    }

    @MainActor func testNewOrderShowsInlineValidationAndSavesAfterCorrections() throws {
        let app = launch()
        openNewOrder(app)
        let extract = app.buttons["new-signing-extract-screenshot"]
        XCTAssertTrue(extract.waitForExistence(timeout: 5))
        extract.tap()
        XCTAssertTrue(app.buttons["Choose Screenshot"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose Image from Files"].exists)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        app.buttons["Save"].tap()
        for (field, message) in [("customerName", "Please enter customer name."), ("signerName", "Please enter signer name."),
                                 ("fee", "Please enter a valid fee."), ("invoiceNumber", "Please enter invoice number.")] {
            let error = app.staticTexts["order-error-\(field)"]
            XCTAssertTrue(error.waitForExistence(timeout: 5))
            XCTAssertEqual(error.label, message)
        }
        XCTAssertTrue(app.staticTexts["order-error-customerName"].isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "New order inline required fields"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        enterOrderField("Acme Title", into: app.textFields["Customer name"], in: app)
        XCTAssertFalse(app.staticTexts["order-error-customerName"].exists)
        XCTAssertTrue(app.staticTexts["order-error-signerName"].exists)
        enterOrderField("Jamie Smith", into: app.textFields["Signer name"], in: app)
        enterOrderField("150", into: app.textFields["Fee"], in: app)
        enterOrderField("200", into: app.textFields["Notarial act fee"], in: app)
        XCTAssertEqual(app.staticTexts["order-error-notarialActFee"].label, "Notarial act fee cannot exceed the total fee.")
        let notarial = app.textFields["Notarial act fee"]
        notarial.tap()
        notarial.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "10")
        XCTAssertFalse(app.staticTexts["order-error-notarialActFee"].exists)
        enterOrderField("INV-1", into: app.textFields["Invoice number"], in: app)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["New Signing"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Signer: Jamie Smith"].exists)
    }

    @MainActor func testNewOrderKeepsServerErrorsInlineAndCanRetry() throws {
        let app = launch()
        openNewOrder(app)
        enterOrderField("Acme Title", into: app.textFields["Customer name"], in: app)
        enterOrderField("Jamie Smith", into: app.textFields["Signer name"], in: app)
        enterOrderField("150", into: app.textFields["Fee"], in: app)
        enterOrderField("SERVER-ERROR", into: app.textFields["Invoice number"], in: app)
        app.buttons["Save"].tap()
        let invoiceError = app.staticTexts["order-error-invoiceNumber"]
        XCTAssertTrue(invoiceError.waitForExistence(timeout: 5))
        XCTAssertEqual(invoiceError.label, "Invoice number is already in use.")
        XCTAssertTrue(invoiceError.isHittable)
        XCTAssertEqual(app.staticTexts["order-error-travelFee"].label, "Parking fee must be zero or greater.")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "New order server field errors"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let invoice = app.textFields["Invoice number"]
        invoice.tap()
        invoice.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "SERVER-ERROR".count) + "INV-2")
        XCTAssertFalse(invoiceError.exists)
        XCTAssertTrue(app.staticTexts["order-error-travelFee"].exists)
        enterOrderField("0", into: app.textFields["Parking and tolls"], in: app)
        XCTAssertFalse(app.staticTexts["order-error-travelFee"].exists)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["New Signing"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Signer: Jamie Smith"].exists)
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

    @MainActor func testCustomersCreateInvoiceExportsSelectedCustomerAndShowsAccessErrors() throws {
        for free in [false, true] {
            let app = launch(freePlan: free, customerInvoices: true)
            XCTAssertTrue(app.buttons["Log In"].waitForExistence(timeout: 10))
            enter("avery@example.test", into: app.textFields["Email"], in: app)
            enter("StrongPass12!", into: app.secureTextFields["Password"], in: app)
            reveal(app.buttons["Log In"], in: app)
            app.buttons["Log In"].tap()
            XCTAssertTrue(app.staticTexts["Dashboard plan"].waitForExistence(timeout: 10))
            app.buttons["Open navigation menu"].tap()
            app.buttons["Customers"].tap()

            let paidOnly = app.buttons["customer-invoice-zenith paid"]
            XCTAssertTrue(paidOnly.waitForExistence(timeout: 5))
            XCTAssertFalse(paidOnly.isEnabled)
            let create = app.buttons["customer-invoice-harbor title"]
            reveal(create, in: app)
            create.tap()
            if free {
                XCTAssertTrue(app.staticTexts["Upgrade to Pro to generate invoices."].waitForExistence(timeout: 5))
                XCTAssertTrue(create.isEnabled)
            } else {
                XCTAssertTrue(app.cells["Copy"].waitForExistence(timeout: 10))
                XCTAssertTrue(app.otherElements["LP.CaptionBar.TopCaption"].label.hasSuffix("harbor-title"))
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "Customer invoice share sheet"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }
            app.terminate()
        }
    }

    @MainActor func testLegalPagesHaveFullWebContentAndReturnToSignIn() throws {
        for (title, lastSection) in [("Terms & Conditions", "9. Limitation of Liability"), ("Privacy Policy", "9. Changes to This Policy")] {
            let app = launch("https://notaryledger.org/signup")
            XCTAssertTrue(app.staticTexts["Set up your desk"].waitForExistence(timeout: 10))
            let link = app.buttons[title]
            reveal(link, in: app)
            link.tap()
            XCTAssertTrue(app.buttons["Sign in"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Last updated July 19, 2026.")).firstMatch.exists)
            let top = XCTAttachment(screenshot: app.screenshot())
            top.name = title + " top"
            top.lifetime = .keepAlways
            add(top)
            let contact = app.buttons["Contact support"]
            for _ in 0..<24 {
                if contact.isHittable { break }
                app.swipeUp(velocity: .fast)
            }
            XCTAssertTrue(app.staticTexts[lastSection].exists)
            XCTAssertTrue(contact.isHittable)
            contact.tap()
            XCTAssertTrue(app.buttons["Send support request"].exists)
            let bottom = XCTAttachment(screenshot: app.screenshot())
            bottom.name = title + " contact form"
            bottom.lifetime = .keepAlways
            add(bottom)
            for _ in 0..<24 {
                if app.buttons["Sign in"].isHittable { break }
                app.swipeDown(velocity: .fast)
            }
            app.buttons["Sign in"].tap()
            XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["Set up your desk"].exists)
            app.terminate()
        }
    }

    @MainActor func testLegalPageFromSidebarReturnsToDashboard() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["Log In"].waitForExistence(timeout: 10))
        enter("avery@example.test", into: app.textFields["Email"], in: app)
        enter("StrongPass12!", into: app.secureTextFields["Password"], in: app)
        reveal(app.buttons["Log In"], in: app)
        app.buttons["Log In"].tap()
        XCTAssertTrue(app.staticTexts["Dashboard plan"].waitForExistence(timeout: 10))
        for title in ["Terms & Conditions", "Privacy Policy"] {
            app.buttons["Open navigation menu"].tap()
            let item = app.buttons[title]
            reveal(item, in: app)
            item.tap()
            let back = app.buttons["Back to dashboard"]
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            back.tap()
            XCTAssertTrue(app.staticTexts["Dashboard plan"].waitForExistence(timeout: 5))
        }
    }

    @MainActor func testFreeAndProPlansAppearOnDashboardAndSidebar() throws {
        for free in [false, true] {
            let app = launch(freePlan: free)
            XCTAssertTrue(app.buttons["Log In"].waitForExistence(timeout: 10))
            enter("avery@example.test", into: app.textFields["Email"], in: app)
            enter("StrongPass12!", into: app.secureTextFields["Password"], in: app)
            reveal(app.buttons["Log In"], in: app)
            app.buttons["Log In"].tap()
            let plan = app.staticTexts["Dashboard plan"]
            XCTAssertTrue(plan.waitForExistence(timeout: 10))
            let expected = "Current plan: " + (free ? "Free" : "Pro")
            let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: plan)
            XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 5), .completed)
            let dashboard = XCTAttachment(screenshot: app.screenshot())
            dashboard.name = free ? "Dashboard Free plan" : "Dashboard Pro plan"
            dashboard.lifetime = .keepAlways
            add(dashboard)
            app.buttons["Open navigation menu"].tap()
            let sidebar = app.staticTexts["Sidebar plan"]
            XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
            XCTAssertEqual(sidebar.label, expected)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = free ? "Sidebar Free plan" : "Sidebar Pro plan"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
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
