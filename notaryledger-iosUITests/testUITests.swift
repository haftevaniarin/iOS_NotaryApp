import XCTest

final class NotaryLedgerSmokeTests: XCTestCase {
    @MainActor func testDashboardNativeTabsAndPlaceholderActions() throws {
        let app = launch(dashboardFixtures: true)
        XCTAssertTrue(app.buttons["Log In"].waitForExistence(timeout: 10))
        enter("avery@example.test", into: app.textFields["Email"], in: app)
        enter("StrongPass12!", into: app.secureTextFields["Password"], in: app)
        reveal(app.buttons["Log In"], in: app); app.buttons["Log In"].tap()
        XCTAssertTrue(app.staticTexts["dashboard-greeting"].waitForExistence(timeout: 10))
        for tab in ["Home", "Signings", "Accounting", "Menu"] { XCTAssertTrue(app.tabBars.buttons[tab].exists) }
        XCTAssertFalse(app.tabBars.buttons["Journal"].exists)
        XCTAssertFalse(app.buttons["dashboard-action-journal"].exists)
        XCTAssertFalse(app.buttons["dashboard-action-mileage"].exists)
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected)
        XCTAssertTrue(app.buttons["dashboard-navigate"].isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Dashboard iPhone 15 loaded"; shot.lifetime = .keepAlways; add(shot)
        for (id, title) in [("signing", "New Signing"), ("expense", "New Expense")] {
            app.buttons["dashboard-action-\(id)"].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Save"].exists)
            if id == "signing" {
                XCTAssertTrue(app.textFields["Signer name"].exists)
            } else {
                XCTAssertTrue(app.textFields["Description"].exists)
            }
            app.buttons["Cancel"].tap()
            XCTAssertTrue(app.staticTexts["dashboard-greeting"].waitForExistence(timeout: 5))
        }
        app.buttons["dashboard-open-file"].tap()
        XCTAssertTrue(app.navigationBars["Signing file"].waitForExistence(timeout: 5)); app.buttons["Done"].tap()
        app.buttons["Notifications"].tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5)); app.buttons["Done"].tap()
        let seeAll = app.buttons["dashboard-see-all"]
        reveal(seeAll, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["dashboard-stat-mileage"].firstMatch.exists)
        seeAll.tap()
        XCTAssertTrue(app.tabBars.buttons["Signings"].isSelected)
        app.tabBars.buttons["Accounting"].tap()
        XCTAssertTrue(app.staticTexts["Accounting"].exists)
        XCTAssertTrue(app.buttons["Invoices"].exists)
        app.buttons["Customers"].tap()
        XCTAssertTrue(app.navigationBars["Customers"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Accounting"].isSelected)
        app.tabBars.buttons["Menu"].tap()
        app.tabBars.buttons["Accounting"].tap()
        XCTAssertTrue(app.buttons["Customers"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Customers"].exists)
        XCTAssertTrue(app.tabBars.buttons["Accounting"].isSelected)
        app.tabBars.buttons["Menu"].tap()
        XCTAssertTrue(app.buttons["Billing"].exists)
        XCTAssertFalse(app.buttons["Customers"].exists)
        XCTAssertFalse(app.buttons["Journal"].exists)
        XCTAssertTrue(app.staticTexts["Menu"].exists)
        XCTAssertLessThan(app.buttons["Profile"].frame.minY, app.buttons["Billing"].frame.minY)
        XCTAssertLessThan(app.buttons["Billing"].frame.minY, app.buttons["Rescission Calculator"].frame.minY)
    }
    @MainActor func testDashboardQuickActionsCreateSigningAndExpenseFromEmptyState() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["Log In"].waitForExistence(timeout: 10))
        enter("avery@example.test", into: app.textFields["Email"], in: app)
        enter("StrongPass12!", into: app.secureTextFields["Password"], in: app)
        reveal(app.buttons["Log In"], in: app); app.buttons["Log In"].tap()
        XCTAssertTrue(app.staticTexts["No signings today"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Add signing"].exists)
        app.buttons["dashboard-action-signing"].tap()
        XCTAssertTrue(app.navigationBars["New Signing"].waitForExistence(timeout: 5))
        enterOrderField("Dashboard Title", into: app.textFields["Customer name"], in: app)
        enterOrderField("Dashboard Signer", into: app.textFields["Signer name"], in: app)
        enterOrderField("150", into: app.textFields["Fee"], in: app)
        enterOrderField("DASHBOARD-1", into: app.textFields["Invoice number"], in: app)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["dashboard-action-expense"].waitForExistence(timeout: 5))
        app.buttons["dashboard-action-expense"].tap()
        XCTAssertTrue(app.navigationBars["New Expense"].waitForExistence(timeout: 5))
        enter("Dashboard supplies", into: app.textFields["Description"], in: app)
        enter("12.50", into: app.textFields["Amount"], in: app)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["dashboard-greeting"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Signings"].tap()
        XCTAssertTrue(app.staticTexts["Signer: Dashboard Signer"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Accounting"].tap()
        app.buttons["Expenses"].tap()
        XCTAssertTrue(app.staticTexts["Dashboard supplies"].waitForExistence(timeout: 5))
    }
    @MainActor func testReportsDirectLinkShowsRetryForUnavailableEndpoint() throws {
        let app = launch("notaryledger://reports", reportsUnavailable: true)
        XCTAssertTrue(app.buttons["Log In"].waitForExistence(timeout: 10))
        enter("avery@example.test", into: app.textFields["Email"], in: app)
        enter("StrongPass12!", into: app.secureTextFields["Password"], in: app)
        reveal(app.buttons["Log In"], in: app); app.buttons["Log In"].tap()
        let error = app.staticTexts["reports-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertEqual(error.label, "This report is not available yet.")
        XCTAssertTrue(app.tabBars.buttons["Accounting"].isSelected)
        let retry = app.buttons["Try again"]
        revealOrderControl(retry, in: app); retry.tap()
        XCTAssertTrue(error.waitForExistence(timeout: 5))
    }

    @MainActor func testAccountingReportsMatchWebChoicesAndResetOnTabChange() throws {
        let app = launch(customerInvoices: true)
        XCTAssertTrue(app.buttons["Log In"].waitForExistence(timeout: 10))
        enter("avery@example.test", into: app.textFields["Email"], in: app)
        enter("StrongPass12!", into: app.secureTextFields["Password"], in: app)
        reveal(app.buttons["Log In"], in: app); app.buttons["Log In"].tap()
        XCTAssertTrue(app.staticTexts["dashboard-greeting"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Accounting"].tap()
        XCTAssertTrue(app.buttons["Tax Summary"].exists)
        app.buttons["Reports"].tap()
        XCTAssertTrue(app.navigationBars["Reports"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["report-metric-grossRevenue"].firstMatch.waitForExistence(timeout: 5))
        for (title, identifier) in [("Income", "report-metric-grossRevenue"), ("Profit & Loss", "report-metric-profitMargin"),
                                     ("Outstanding Payments", "report-metric-totalOutstanding"), ("Mileage", "report-metric-totalBusinessMiles"),
                                     ("Expenses", "report-metric-expenseCount"), ("Clients", "report-row-clients-0")] {
            let picker = app.buttons["Report"]
            revealOrderControl(picker, in: app); picker.tap()
            app.buttons[title].tap()
            let value = app.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(value.waitForExistence(timeout: 5))
            if title == "Clients" {
                XCTAssertTrue(value.staticTexts["Harbor Title"].exists)
                XCTAssertTrue(value.staticTexts["$300.30"].exists)
            }
        }
        app.tabBars.buttons["Home"].tap()
        app.tabBars.buttons["Accounting"].tap()
        XCTAssertTrue(app.buttons["Reports"].exists)
        XCTAssertFalse(app.navigationBars["Reports"].exists)
    }

    @MainActor func testNewSigningSuggestsCustomersAndPreservesEnteredDetails() throws {
        let app = launch(customerInvoices: true)
        openNewOrder(app)
        enterOrderField("Draft signer", into: app.textFields["Signer name"], in: app)
        enterOrderField("har", into: app.textFields["Customer name"], in: app)
        let suggestion = app.buttons["customer-suggestion-harbor title"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["customer-suggestion-alder title"].exists)
        suggestion.tap()
        XCTAssertEqual(app.textFields["Customer name"].value as? String, "Harbor Title")
        XCTAssertEqual(app.textFields["Signer name"].value as? String, "Draft signer")
        XCTAssertFalse(suggestion.exists)
        let customer = app.textFields["Customer name"]
        revealOrderControl(customer, in: app)
        customer.tap()
        customer.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Harbor Title".count) + "New customer")
        XCTAssertFalse(app.staticTexts["Existing customers"].exists)
        XCTAssertEqual(customer.value as? String, "New customer")
        XCTAssertEqual(app.textFields["Signer name"].value as? String, "Draft signer")
        app.buttons["Cancel"].tap()
    }
    @MainActor func testLeavingPagesClearsSearchAndResetsHubNavigation() throws {
        let app = launch(customerInvoices: true)
        XCTAssertTrue(app.buttons["Log In"].waitForExistence(timeout: 10))
        enter("avery@example.test", into: app.textFields["Email"], in: app)
        enter("StrongPass12!", into: app.secureTextFields["Password"], in: app)
        reveal(app.buttons["Log In"], in: app); app.buttons["Log In"].tap()
        XCTAssertTrue(app.staticTexts["dashboard-greeting"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Signings"].tap()
        enter("Harbor\n", into: app.textFields["Search"], in: app)
        app.tabBars.buttons["Home"].tap()
        app.tabBars.buttons["Signings"].tap()
        assertEmptySearch(app.textFields["Search"])
        for (page, search) in [("Customers", "Search customers"), ("Expenses", "Search expenses")] {
            app.tabBars.buttons["Home"].tap()
            app.tabBars.buttons["Accounting"].tap()
            app.buttons[page].tap()
            XCTAssertTrue(app.navigationBars[page].waitForExistence(timeout: 5))
            enter("Harbor\n", into: app.textFields[search], in: app)
            app.tabBars.buttons["Home"].tap()
            app.tabBars.buttons["Accounting"].tap()
            XCTAssertTrue(app.buttons[page].waitForExistence(timeout: 5))
            XCTAssertFalse(app.navigationBars[page].exists)
            app.buttons[page].tap()
            assertEmptySearch(app.textFields[search])
            app.navigationBars[page].buttons.element(boundBy: 0).tap()
            app.buttons[page].tap()
            assertEmptySearch(app.textFields[search])
        }
        app.tabBars.buttons["Menu"].tap()
        XCTAssertFalse(app.buttons["Customers"].exists)
        app.buttons["Profile"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Accounting"].tap()
        XCTAssertTrue(app.buttons["Customers"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Menu"].tap()
        XCTAssertTrue(app.buttons["Profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Billing"].exists)
        XCTAssertFalse(app.navigationBars["Profile"].exists)
    }
    @MainActor private func assertEmptySearch(_ field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), file: file, line: line)
        let value = field.value as? String
        XCTAssertTrue(value == "" || value == field.placeholderValue, "Search should be empty after leaving the page", file: file, line: line)
    }
    @MainActor func testStripeBillingNavigationHasNoPaymentMethodControls() throws {
        let app = launch("notaryledger://billing", stripeBillingFixtures: true)
        XCTAssertTrue(app.buttons["Log In"].waitForExistence(timeout: 10))
        enter("avery@example.test", into: app.textFields["Email"], in: app)
        enter("StrongPass12!", into: app.secureTextFields["Password"], in: app)
        reveal(app.buttons["Log In"], in: app)
        app.buttons["Log In"].tap()
        let plans = app.buttons["billing-view-plans"]
        XCTAssertTrue(plans.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Payment method"].exists)
        XCTAssertTrue(app.buttons["billing-refresh"].exists)
        plans.tap()
        XCTAssertTrue(app.staticTexts["Plans"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["restore-purchases"].exists)
        XCTAssertTrue(app.buttons["plans-subscribe"].exists)
        XCTAssertEqual(app.buttons["plans-subscribe"].label, "Subscribe")
        let monthly = app.buttons["Monthly billing"]
        monthly.tap()
        XCTAssertTrue(monthly.isSelected)
        XCTAssertFalse(app.buttons["Update Payment Details"].exists)
        app.buttons["plans-back"].tap()
        XCTAssertTrue(plans.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["billing-compare-plans"].exists)
    }
    @MainActor private func launch(_ link: String? = nil, freePlan: Bool = false, customerInvoices: Bool = false, cancelRefresh: Bool = false, stripeBillingFixtures: Bool = false, appointmentFeedback: Bool = false, dashboardFixtures: Bool = false, reportsUnavailable: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--auth-fixtures"]
        if freePlan { app.launchArguments.append("--billing-free") }
        if customerInvoices { app.launchArguments.append("--customer-invoice-fixtures") }
        if cancelRefresh { app.launchArguments.append("--cancel-dashboard-refresh") }
        if stripeBillingFixtures { app.launchArguments.append("--stripe-billing-ui-fixtures") }
        if appointmentFeedback { app.launchArguments.append("--appointment-feedback-fixtures") }
        if dashboardFixtures { app.launchArguments.append("--dashboard-design-fixtures") }
        if reportsUnavailable { app.launchArguments.append("--reports-unavailable") }
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

    @MainActor func testDashboardRefreshKeepsLoadedDataAndSharedPlan() throws {
        let app = launch(customerInvoices: true)
        XCTAssertTrue(app.buttons["Log In"].waitForExistence(timeout: 10))
        enter("avery@example.test", into: app.textFields["Email"], in: app)
        enter("StrongPass12!", into: app.secureTextFields["Password"], in: app)
        reveal(app.buttons["Log In"], in: app); app.buttons["Log In"].tap()
        XCTAssertTrue(app.staticTexts["dashboard-greeting"].waitForExistence(timeout: 10))
        let income = app.descendants(matching: .any)["dashboard-stat-net-income"].firstMatch
        let label = income.label
        app.scrollViews["dashboard-content"].swipeDown()
        XCTAssertFalse(app.otherElements["dashboard-error"].exists)
        XCTAssertEqual(income.label, label)
        app.tabBars.buttons["Menu"].tap()
        let plan = app.staticTexts["Menu plan"]
        XCTAssertTrue(plan.waitForExistence(timeout: 5))
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Current plan: Pro"), object: plan)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 5), .completed)
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
        XCTAssertTrue(app.staticTexts["dashboard-greeting"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Signings"].tap()
        app.buttons["New Signing"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
    }

    @MainActor private func enterOrderField(_ value: String, into field: XCUIElement, in app: XCUIApplication) {
        revealOrderControl(field, in: app)
        field.tap()
        field.typeText(value)
    }

    @MainActor private func revealOrderControl(_ field: XCUIElement, in app: XCUIApplication) {
        // Keep the control between the modal navigation bar and keyboard.
        // isHittable alone can include a field obscured by the navigation bar.
        for _ in 0..<12 {
            let top = app.navigationBars.firstMatch.frame.maxY + 24
            let keyboard = app.keyboards.firstMatch
            let bottom = keyboard.exists ? keyboard.frame.minY - 24 : app.frame.maxY - 70
            if field.isHittable && field.frame.midY > top && field.frame.midY < bottom { break }
            let center = app.coordinate(withNormalizedOffset: .zero)
            let distance = min(280, max(80, abs(field.frame.midY - (top + bottom) / 2)))
            let startY = field.frame.midY <= top ? top + 20 : bottom - 20
            let endY = field.frame.midY <= top ? min(bottom - 20, startY + distance) : max(top + 20, startY - distance)
            center.withOffset(CGVector(dx: app.frame.midX, dy: startY))
                .press(forDuration: 0.05, thenDragTo: center.withOffset(CGVector(dx: app.frame.midX, dy: endY)))
        }
    }

    @MainActor func testAppointmentFeedbackPreservesDraftAndClearsResolvedConflict() throws {
        let app = launch(appointmentFeedback: true)
        openNewOrder(app)
        enterOrderField("Draft title", into: app.textFields["Customer name"], in: app)
        enterOrderField("Draft signer", into: app.textFields["Signer name"], in: app)
        let type = app.buttons["Signing type"]
        revealOrderControl(type, in: app); type.tap(); app.buttons["Refinance"].tap()
        let time = app.buttons["Time"]
        revealOrderControl(time, in: app); time.tap(); app.buttons["Done"].tap()
        let warning = app.staticTexts["order-schedule-warning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        let viewOrder = app.buttons["view-conflicting-order"]
        revealOrderControl(viewOrder, in: app); viewOrder.tap()
        XCTAssertTrue(app.staticTexts["Existing signer"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        let signer = app.textFields["Signer name"]
        revealOrderControl(signer, in: app)
        XCTAssertEqual(signer.value as? String, "Draft signer")
        XCTAssertEqual(app.textFields["Customer name"].value as? String, "Draft title")
        revealOrderControl(time, in: app); time.tap(); app.buttons["Clear Time"].tap()
        XCTAssertFalse(warning.exists)
        let rescission = app.staticTexts["order-rescission-message"]
        revealOrderControl(rescission, in: app)
        XCTAssertTrue(rescission.label.contains("Based on the signing date"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Inline rescission after resolving schedule conflict"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["Cancel"].tap()
    }

    @MainActor func testServerScheduleConflictAppearsInlineAndAllowsCorrectedRetry() throws {
        let app = launch(appointmentFeedback: true)
        openNewOrder(app)
        enterOrderField("Draft title", into: app.textFields["Customer name"], in: app)
        enterOrderField("Draft signer", into: app.textFields["Signer name"], in: app)
        enterOrderField("150", into: app.textFields["Fee"], in: app)
        enterOrderField("SERVER-SCHEDULE-CONFLICT", into: app.textFields["Invoice number"], in: app)
        app.buttons["Save"].tap()
        let error = app.staticTexts["order-error-schedule"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("Choose another time"))
        let time = app.buttons["Time"]
        revealOrderControl(time, in: app); time.tap(); app.buttons["Done"].tap()
        XCTAssertFalse(error.exists)
        XCTAssertTrue(app.staticTexts["order-schedule-warning"].exists)
        let invoice = app.textFields["Invoice number"]
        revealOrderControl(invoice, in: app); invoice.tap()
        invoice.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "SERVER-SCHEDULE-CONFLICT".count) + "INV-CORRECTED")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["New Signing"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Signer: Draft signer"].exists)
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
            XCTAssertTrue(app.staticTexts["dashboard-greeting"].waitForExistence(timeout: 10))
            app.tabBars.buttons["Accounting"].tap()
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

    @MainActor func testLegalPagesFromMenuReturnToHome() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["Log In"].waitForExistence(timeout: 10))
        enter("avery@example.test", into: app.textFields["Email"], in: app)
        enter("StrongPass12!", into: app.secureTextFields["Password"], in: app)
        reveal(app.buttons["Log In"], in: app)
        app.buttons["Log In"].tap()
        XCTAssertTrue(app.staticTexts["dashboard-greeting"].waitForExistence(timeout: 10))
        for title in ["Terms & Conditions", "Privacy Policy"] {
            app.tabBars.buttons["Menu"].tap()
            let item = app.buttons[title]
            reveal(item, in: app)
            item.tap()
            let back = app.buttons["Back to dashboard"]
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            back.tap()
            XCTAssertTrue(app.staticTexts["dashboard-greeting"].waitForExistence(timeout: 5))
        }
    }

    @MainActor func testFreeAndProPlansRemainAvailableInMenu() throws {
        for free in [false, true] {
            let app = launch(freePlan: free)
            XCTAssertTrue(app.buttons["Log In"].waitForExistence(timeout: 10))
            enter("avery@example.test", into: app.textFields["Email"], in: app)
            enter("StrongPass12!", into: app.secureTextFields["Password"], in: app)
            reveal(app.buttons["Log In"], in: app); app.buttons["Log In"].tap()
            XCTAssertTrue(app.staticTexts["dashboard-greeting"].waitForExistence(timeout: 10))
            app.tabBars.buttons["Menu"].tap()
            let plan = app.staticTexts["Menu plan"]
            XCTAssertTrue(plan.waitForExistence(timeout: 5))
            let expected = "Current plan: " + (free ? "Free" : "Pro")
            let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: plan)
            XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 5), .completed)
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
