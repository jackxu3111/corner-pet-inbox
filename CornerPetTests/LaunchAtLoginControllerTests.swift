import XCTest

@testable import CornerPet

@MainActor
final class LaunchAtLoginControllerTests: XCTestCase {
    func testInitialStateReflectsServiceInsteadOfStoredPreference() {
        let service = FakeLaunchAtLoginService(status: .requiresApproval)

        let controller = LaunchAtLoginController(service: service)

        XCTAssertEqual(controller.state, .requiresApproval)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertNil(controller.errorMessage)
    }

    func testSuccessfulEnableRefreshesTheResultingSystemStatus() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(true)

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(controller.state, .requiresApproval)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertNil(controller.errorMessage)
    }

    func testRegisterFailurePublishesErrorAndKeepsRealSystemStatus() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.registerError = TestError.registrationDenied
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(true)

        XCTAssertEqual(controller.state, .disabled)
        XCTAssertEqual(controller.errorMessage, TestError.registrationDenied.localizedDescription)
    }

    func testLifecycleRefreshClearsAStaleOperationErrorAndReadsCurrentStatus() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.registerError = TestError.registrationDenied
        let controller = LaunchAtLoginController(service: service)
        controller.setEnabled(true)
        service.status = .enabled

        controller.refresh()

        XCTAssertEqual(controller.state, .enabled)
        XCTAssertNil(controller.errorMessage)
    }

    func testSuccessfulDisableRefreshesTheResultingSystemStatus() {
        let service = FakeLaunchAtLoginService(status: .enabled)
        service.statusAfterUnregister = .notRegistered
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(false)

        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(controller.state, .disabled)
        XCTAssertFalse(controller.isEnabled)
    }

    func testUnregisterFailureKeepsEnabledStateAndPublishesError() {
        let service = FakeLaunchAtLoginService(status: .enabled)
        service.unregisterError = TestError.registrationDenied
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(false)

        XCTAssertEqual(controller.state, .enabled)
        XCTAssertTrue(controller.isEnabled)
        XCTAssertNotNil(controller.errorMessage)
    }

    func testNotFoundIsUnavailableAndCanOpenSystemSettings() {
        let service = FakeLaunchAtLoginService(status: .notFound)
        let controller = LaunchAtLoginController(service: service)

        controller.openSystemSettings()

        XCTAssertEqual(controller.state, .unavailable)
        XCTAssertEqual(service.openSystemSettingsCallCount, 1)
    }
}

@MainActor
private final class FakeLaunchAtLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginServiceStatus
    var statusAfterRegister: LaunchAtLoginServiceStatus?
    var statusAfterUnregister: LaunchAtLoginServiceStatus?
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var openSystemSettingsCallCount = 0

    init(status: LaunchAtLoginServiceStatus) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        if let registerError { throw registerError }
        if let statusAfterRegister { status = statusAfterRegister }
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError { throw unregisterError }
        if let statusAfterUnregister { status = statusAfterUnregister }
    }

    func openSystemSettings() {
        openSystemSettingsCallCount += 1
    }
}

private enum TestError: LocalizedError {
    case registrationDenied

    var errorDescription: String? {
        "Registration denied for testing"
    }
}
