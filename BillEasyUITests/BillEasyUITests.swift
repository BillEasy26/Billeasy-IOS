//
//  BillEasyUITests.swift
//  BillEasyUITests
//
//  Created by Samuel Jammes  on 10/03/26.
//

import XCTest

final class BillEasyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testHomeScreenShowsPrimaryActions() throws {
        launchApp(resetData: true, authenticated: false)
        XCTAssertTrue(app.buttons["home.registerButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.loginButton"].exists)
        XCTAssertTrue(app.buttons["home.appleButton"].exists)
        XCTAssertTrue(app.buttons["home.googleButton"].exists)
    }

    @MainActor
    func testLoginShowsValidationAlertWhenEmailIsEmpty() throws {
        launchApp(resetData: true, authenticated: false)
        app.buttons["home.loginButton"].tap()
        XCTAssertTrue(app.buttons["login.submitButton"].waitForExistence(timeout: 5))

        app.buttons["login.submitButton"].tap()
        let requiredAlert = app.alerts["Dados incompletos"]
        XCTAssertTrue(requiredAlert.waitForExistence(timeout: 5))
        requiredAlert.buttons["OK"].tap()
    }

    @MainActor
    func testForgotPasswordFlowShowsRecoveryScreens() throws {
        launchApp(resetData: true, authenticated: false)
        app.buttons["home.loginButton"].tap()
        XCTAssertTrue(app.buttons["login.forgotPasswordButton"].waitForExistence(timeout: 5))

        app.buttons["login.forgotPasswordButton"].tap()

        XCTAssertTrue(app.staticTexts["passwordRecovery.titleLabel"].waitForExistence(timeout: 5))
        let recoveryEmailField = app.textFields["passwordRecovery.emailField"]
        XCTAssertTrue(recoveryEmailField.exists)
        XCTAssertTrue(app.buttons["passwordRecovery.sendButton"].exists)
        XCTAssertTrue(app.buttons["passwordRecovery.secondaryButton"].exists)

        enterText("qa@billeasy.ai", into: recoveryEmailField)
        app.buttons["passwordRecovery.sendButton"].tap()

        XCTAssertTrue(app.staticTexts["passwordRecovery.successTitleLabel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["passwordRecovery.homeButton"].exists)
    }

    @MainActor
    func testHomeScreenShowsWebGetStartedAction() throws {
        launchApp(resetData: true, authenticated: false)
        XCTAssertTrue(app.buttons["home.registerButton"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["home.registerButton"].label, "COMECE GRÁTIS")
    }

    @MainActor
    func testLoginGoogleWithMockOAuthAuthenticatesUser() throws {
        launchApp(
            resetData: true,
            authenticated: false,
            environment: googleOAuthMockEnvironment()
        )
        app.buttons["home.loginButton"].tap()
        let googleButton = app.descendants(matching: .any)["login.googleButton"]
        XCTAssertTrue(googleButton.waitForExistence(timeout: 8))

        googleButton.tap()

        XCTAssertTrue(app.buttons["tab.profile"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testHomeGoogleWithMockOAuthAuthenticatesUser() throws {
        launchApp(
            resetData: true,
            authenticated: false,
            environment: googleOAuthMockEnvironment()
        )

        let googleButton = app.buttons["home.googleButton"]
        XCTAssertTrue(googleButton.waitForExistence(timeout: 5))
        googleButton.tap()

        XCTAssertTrue(app.buttons["tab.profile"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testLoginScreenShowsWebGetStartedAction() throws {
        launchApp(resetData: true, authenticated: false)
        app.buttons["home.loginButton"].tap()

        let getStartedButton = app.buttons["login.signUpButton"]
        XCTAssertTrue(getStartedButton.waitForExistence(timeout: 5))
        XCTAssertEqual(getStartedButton.label, "Comece grátis")
    }

    @MainActor
    func testRegisterConfirmationPreviewShowsPrimaryActions() throws {
        launchApp(
            resetData: true,
            authenticated: false,
            environment: ["UITEST_REGISTER_CONFIRMATION_EMAIL": "qa@billeasy.ai"]
        )

        XCTAssertTrue(app.staticTexts["registerConfirmation.titleLabel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["registerConfirmation.headlineLabel"].exists)
        XCTAssertTrue(app.buttons["registerConfirmation.resendButton"].exists)
        XCTAssertTrue(app.buttons["registerConfirmation.homeButton"].exists)
    }

    @MainActor
    func testContractFileExtractionSuccessShowsPrefilledFormInLightAndDark() throws {
        let previewPDFPath = "/tmp/billeasy-pdf-review/contrato-teste.pdf"
        let screenshotsDirectory = URL(fileURLWithPath: "/tmp/billeasy-pdf-review/screens", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotsDirectory, withIntermediateDirectories: true)

        let sharedEnvironment = [
            "UITEST_CONTRACT_FILE_REVIEW_PATH": previewPDFPath
        ]

        launchApp(
            resetData: true,
            authenticated: false,
            environment: sharedEnvironment.merging(["UITEST_FORCE_DARK_MODE": "0"]) { _, new in new }
        )

        XCTAssertTrue(app.textFields["contracts.subjectField"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.textFields["contracts.subjectField"].value as? String, "Acordo de Parcelamento")
        XCTAssertEqual(app.textFields["contracts.amountField"].value as? String, "R$ 2.500,00")
        XCTAssertFalse(app.otherElements["contracts.fileReview.card"].exists)
        try saveScreenshot(named: "uitest-file-review-light.png", into: screenshotsDirectory)

        app.terminate()

        launchApp(
            resetData: true,
            authenticated: false,
            environment: sharedEnvironment.merging(["UITEST_FORCE_DARK_MODE": "1"]) { _, new in new }
        )

        XCTAssertTrue(app.textFields["contracts.subjectField"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.textFields["contracts.subjectField"].value as? String, "Acordo de Parcelamento")
        XCTAssertEqual(app.textFields["contracts.amountField"].value as? String, "R$ 2.500,00")
        XCTAssertFalse(app.otherElements["contracts.fileReview.card"].exists)
        try saveScreenshot(named: "uitest-file-review-dark.png", into: screenshotsDirectory)
    }

    @MainActor
    func testBottomTabCanOpenProfileScreen() throws {
        launchApp(resetData: true, authenticated: true)
        XCTAssertTrue(app.buttons["tab.profile"].waitForExistence(timeout: 8))
        app.buttons["tab.profile"].tap()

        XCTAssertTrue(
            waitForAnyElement(
                [
                    app.otherElements["profile.screen"],
                    app.textFields["profile.fullNameField"],
                    app.buttons["profile.changePhotoButton"]
                ],
                timeout: 10
            )
        )
    }

    @MainActor
    func testProfilePrivacyScreenShowsLGPDFlow() throws {
        launchApp(resetData: true, authenticated: true)
        XCTAssertTrue(app.buttons["tab.profile"].waitForExistence(timeout: 8))
        app.buttons["tab.profile"].tap()

        let privacyButton = app.buttons["profile.privacyButton"]
        XCTAssertTrue(privacyButton.waitForExistence(timeout: 8))
        privacyButton.tap()

        XCTAssertTrue(app.otherElements["privacy.screen"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["privacy.viewDataButton"].exists)
        XCTAssertTrue(app.buttons["privacy.exportButton"].exists)
        XCTAssertTrue(app.buttons["privacy.deleteAccountButton"].exists)

        app.buttons["privacy.deleteAccountButton"].tap()

        let deleteAlert = app.alerts["Excluir conta"]
        XCTAssertTrue(deleteAlert.waitForExistence(timeout: 5))
        deleteAlert.buttons["Agora não"].tap()
    }

    @MainActor
    func testBottomTabShowsDebtorLocatorShortcut() throws {
        launchApp(resetData: true, authenticated: true)
        XCTAssertTrue(app.buttons["tab.locate"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["tab.locate"].label, "Localizar")
    }

    @MainActor
    func testSideMenuDoesNotShowMyPlanEntry() throws {
        launchApp(resetData: true, authenticated: true)
        XCTAssertTrue(app.buttons["main.menuButton"].waitForExistence(timeout: 8))
        app.buttons["main.menuButton"].tap()

        XCTAssertTrue(app.buttons["menu.newContract"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["menu.subscription"].exists)
    }

    @MainActor
    func testSideMenuCanOpenNewContractForm() throws {
        launchApp(resetData: true, authenticated: true)
        XCTAssertTrue(app.buttons["main.menuButton"].waitForExistence(timeout: 8))
        app.buttons["main.menuButton"].tap()

        XCTAssertTrue(app.buttons["menu.newContract"].waitForExistence(timeout: 5))
        app.buttons["menu.newContract"].tap()

        XCTAssertTrue(app.buttons["contracts.method.file"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["contracts.method.ai"].exists)
        XCTAssertTrue(app.textFields["contracts.subjectField"].exists)
        XCTAssertTrue(app.textFields["contracts.amountField"].exists)
        XCTAssertTrue(app.textFields["contracts.debtor.nameField"].exists)
        XCTAssertTrue(app.buttons["contracts.creditor.personTypeButton"].exists)
        XCTAssertTrue(app.buttons["contracts.creditor.pixKeyTypeButton"].exists)
        XCTAssertTrue(app.buttons["contracts.submitButton"].exists)
    }

    @MainActor
    func testNewContractFileOptionIsAvailable() throws {
        launchApp(resetData: true, authenticated: true)
        XCTAssertTrue(app.buttons["main.menuButton"].waitForExistence(timeout: 8))
        app.buttons["main.menuButton"].tap()

        XCTAssertTrue(app.buttons["menu.newContract"].waitForExistence(timeout: 5))
        app.buttons["menu.newContract"].tap()

        let fileButton = app.buttons["contracts.method.file"]
        XCTAssertTrue(fileButton.waitForExistence(timeout: 6))
        XCTAssertTrue(fileButton.isHittable)
    }

    @MainActor
    func testNewContractAIOptionOpensAIGenerationModal() throws {
        launchApp(resetData: true, authenticated: true)
        XCTAssertTrue(app.buttons["main.menuButton"].waitForExistence(timeout: 8))
        app.buttons["main.menuButton"].tap()

        XCTAssertTrue(app.buttons["menu.newContract"].waitForExistence(timeout: 5))
        app.buttons["menu.newContract"].tap()

        let aiButton = app.buttons["contracts.method.ai"]
        XCTAssertTrue(aiButton.waitForExistence(timeout: 6))
        XCTAssertTrue(aiButton.isHittable)

        aiButton.tap()

        XCTAssertTrue(app.otherElements["contracts.aiGenerator.card"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["contracts.aiGenerator.titleLabel"].exists)
        XCTAssertTrue(app.buttons["contracts.aiGenerator.generateButton"].exists)
    }

    private func launchApp(
        resetData: Bool,
        authenticated: Bool,
        environment: [String: String] = [:]
    ) {
        app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait

        var arguments = [
            "-ui-testing",
            "-disable-ui-animations",
            "-skip-permission-onboarding"
        ]

        if resetData {
            arguments.append("-reset-local-data")
        }

        if authenticated {
            arguments.append("-seed-auth-session")
        }

        app.launchArguments = arguments
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        environment.forEach { key, value in
            app.launchEnvironment[key] = value
        }
        app.launch()
        XCUIDevice.shared.orientation = .portrait
    }

    private func googleOAuthMockEnvironment() -> [String: String] {
        [
            "UITEST_GOOGLE_OAUTH_GOOGLE_ID": "google-ui-test-123",
            "UITEST_GOOGLE_OAUTH_EMAIL": "google.ui@billeasy.ai",
            "UITEST_GOOGLE_OAUTH_NAME": "Google UI Test"
        ]
    }

    private func saveScreenshot(named name: String, into directory: URL) throws {
        let screenshot = XCUIScreen.main.screenshot().pngRepresentation
        try screenshot.write(to: directory.appendingPathComponent(name))
    }

    private func enterText(_ text: String, into element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        if !element.isHittable {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else {
            element.tap()
        }
        element.tap()
        app.typeText(text)
    }

    private func waitForAnyElement(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if elements.contains(where: \.exists) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline

        return elements.contains(where: \.exists)
    }
}
