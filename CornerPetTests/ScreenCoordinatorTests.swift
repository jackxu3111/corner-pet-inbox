import CoreGraphics
import Foundation
import XCTest

@testable import CornerPet

@MainActor
final class ScreenCoordinatorTests: XCTestCase {
    func testPrimaryScopeUsesSystemPrimaryDisplayInsteadOfProviderOrder() {
        let screens = [screen(id: 11, x: -1_000), screen(id: 22, x: 0)]
        let coordinator = ScreenCoordinator(
            screensProvider: { screens },
            primaryDisplayIDProvider: { 22 }
        )
        var configurations: [ScreenConfiguration] = []
        coordinator.onChange = { configurations.append($0) }

        coordinator.start(scope: .primary)

        XCTAssertEqual(configurations.count, 1)
        XCTAssertEqual(configurations[0].primaryDisplayID, 22)
        XCTAssertEqual(configurations[0].enabledScreens.map(\.id), [22])
    }

    func testAllScopePublishesEveryScreenInStableProviderOrder() {
        let screens = [screen(id: 30, x: 0), screen(id: 10, x: 1_000)]
        let coordinator = ScreenCoordinator(
            screensProvider: { screens },
            primaryDisplayIDProvider: { 30 }
        )
        var latest: ScreenConfiguration?
        coordinator.onChange = { latest = $0 }

        coordinator.start(scope: .all)

        XCTAssertEqual(latest?.enabledScreens.map(\.id), [30, 10])
        XCTAssertEqual(latest?.allScreens.map(\.id), [30, 10])
    }

    func testMissingPrimaryFallsBackToFirstAvailableScreen() {
        let coordinator = ScreenCoordinator(
            screensProvider: { [self.screen(id: 7, x: 400), self.screen(id: 8, x: 900)] },
            primaryDisplayIDProvider: { 999 }
        )
        var latest: ScreenConfiguration?
        coordinator.onChange = { latest = $0 }

        coordinator.start(scope: .primary)

        XCTAssertEqual(latest?.primaryDisplayID, 7)
        XCTAssertEqual(latest?.enabledScreens.map(\.id), [7])
    }

    func testScopeChangeImmediatelyPublishesDifferentEnabledScreens() {
        let screens = [screen(id: 1, x: 0), screen(id: 2, x: 1_000)]
        let coordinator = ScreenCoordinator(
            screensProvider: { screens },
            primaryDisplayIDProvider: { 1 }
        )
        var enabledIDs: [[UInt32]] = []
        coordinator.onChange = { enabledIDs.append($0.enabledScreens.map(\.id)) }

        coordinator.start(scope: .primary)
        coordinator.updateScope(.all)

        XCTAssertEqual(enabledIDs, [[1], [1, 2]])
    }

    func testScreenNotificationRebuildsAndPublishesChangedGeometry() async {
        let center = NotificationCenter()
        let name = Notification.Name("ScreenCoordinatorTests.changed")
        var screens = [screen(id: 1, x: 0)]
        let coordinator = ScreenCoordinator(
            screensProvider: { screens },
            primaryDisplayIDProvider: { 1 },
            notificationCenter: center,
            screenParametersNotification: name
        )
        let changed = expectation(description: "screen configuration changed")
        var values: [ScreenConfiguration] = []
        coordinator.onChange = {
            values.append($0)
            if values.count == 2 { changed.fulfill() }
        }
        coordinator.start(scope: .all)

        screens = [screen(id: 1, x: 20), screen(id: 2, x: 1_000)]
        center.post(name: name, object: nil)
        await fulfillment(of: [changed], timeout: 1)

        XCTAssertEqual(values[1].enabledScreens.map(\.id), [1, 2])
        XCTAssertEqual(values[1].enabledScreens[0].frame.minX, 20)
    }

    func testStopRemovesScreenChangeObservation() async {
        let center = NotificationCenter()
        let name = Notification.Name("ScreenCoordinatorTests.stopped")
        var screens = [screen(id: 1, x: 0)]
        let coordinator = ScreenCoordinator(
            screensProvider: { screens },
            primaryDisplayIDProvider: { 1 },
            notificationCenter: center,
            screenParametersNotification: name
        )
        var publishCount = 0
        coordinator.onChange = { _ in publishCount += 1 }
        coordinator.start(scope: .all)
        coordinator.stop()

        screens = [screen(id: 1, x: 200)]
        center.post(name: name, object: nil)
        await Task.yield()

        XCTAssertEqual(publishCount, 1)
        XCTAssertFalse(coordinator.isRunning)
    }

    private func screen(id: UInt32, x: CGFloat) -> ScreenSnapshot {
        ScreenSnapshot(
            id: id,
            frame: CGRect(x: x, y: 0, width: 1_000, height: 800),
            visibleFrame: CGRect(x: x, y: 0, width: 1_000, height: 760)
        )
    }
}
