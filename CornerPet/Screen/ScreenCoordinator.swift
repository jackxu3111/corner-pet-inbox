import AppKit
import CoreGraphics
import Foundation

struct ScreenSnapshot: Equatable, Sendable {
    let id: UInt32
    let frame: CGRect
    let visibleFrame: CGRect
}

struct ScreenConfiguration: Equatable, Sendable {
    let allScreens: [ScreenSnapshot]
    let enabledScreens: [ScreenSnapshot]
    let primaryDisplayID: UInt32?

    var primaryScreen: ScreenSnapshot? {
        guard let primaryDisplayID else { return nil }
        return allScreens.first { $0.id == primaryDisplayID }
    }
}

@MainActor
final class ScreenCoordinator {
    typealias ScreensProvider = @MainActor () -> [ScreenSnapshot]
    typealias PrimaryDisplayIDProvider = @MainActor () -> UInt32

    private let screensProvider: ScreensProvider
    private let primaryDisplayIDProvider: PrimaryDisplayIDProvider
    private let notificationCenter: NotificationCenter
    private let screenParametersNotification: Notification.Name

    private var scope: DisplayScope = .primary
    private var observer: NSObjectProtocol?
    private(set) var currentConfiguration: ScreenConfiguration?

    private(set) var isRunning = false
    var onChange: ((ScreenConfiguration) -> Void)?

    init(
        screensProvider: @escaping ScreensProvider = { ScreenCoordinator.currentScreens() },
        primaryDisplayIDProvider: @escaping PrimaryDisplayIDProvider = { CGMainDisplayID() },
        notificationCenter: NotificationCenter = .default,
        screenParametersNotification: Notification.Name = NSApplication.didChangeScreenParametersNotification
    ) {
        self.screensProvider = screensProvider
        self.primaryDisplayIDProvider = primaryDisplayIDProvider
        self.notificationCenter = notificationCenter
        self.screenParametersNotification = screenParametersNotification
    }

    func start(scope: DisplayScope) {
        guard !isRunning else {
            updateScope(scope)
            return
        }

        self.scope = scope
        isRunning = true
        observer = notificationCenter.addObserver(
            forName: screenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        refresh(force: true)
    }

    func updateScope(_ scope: DisplayScope) {
        guard self.scope != scope else { return }
        self.scope = scope
        guard isRunning else { return }
        refresh(force: true)
    }

    func stop() {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
        observer = nil
        currentConfiguration = nil
        isRunning = false
    }

    func refresh() {
        refresh(force: false)
    }

    private func refresh(force: Bool) {
        let allScreens = screensProvider()
        let requestedPrimaryID = primaryDisplayIDProvider()
        let primaryDisplayID = allScreens.contains { $0.id == requestedPrimaryID }
            ? requestedPrimaryID
            : allScreens.first?.id
        let enabledScreens: [ScreenSnapshot]
        switch scope {
        case .primary:
            enabledScreens = primaryDisplayID.flatMap { primaryID in
                allScreens.first { $0.id == primaryID }
            }.map { [$0] } ?? []
        case .all:
            enabledScreens = allScreens
        }
        let configuration = ScreenConfiguration(
            allScreens: allScreens,
            enabledScreens: enabledScreens,
            primaryDisplayID: primaryDisplayID
        )
        guard force || configuration != currentConfiguration else { return }
        currentConfiguration = configuration
        onChange?(configuration)
    }

    private static func currentScreens() -> [ScreenSnapshot] {
        NSScreen.screens.compactMap { screen in
            guard let id = (
                screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? NSNumber
            )?.uint32Value else {
                return nil
            }
            return ScreenSnapshot(
                id: id,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame
            )
        }
    }
}
