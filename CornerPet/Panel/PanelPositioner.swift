import CoreGraphics

struct PanelScreenGeometry: Equatable {
    let id: UInt32
    let frame: CGRect
    let visibleFrame: CGRect
}

struct PanelReturnTarget: Equatable {
    let screenID: UInt32
    let corner: TriggerCorner
    let frame: CGRect
}

struct PanelPositioner {
    static let defaultSize = CGSize(width: 360, height: 450)
    static let edgeInset: CGFloat = 0

    private static let cornerOrder: [TriggerCorner] = [
        .topLeft,
        .topRight,
        .bottomLeft,
        .bottomRight
    ]

    static func frame(
        inside visibleFrame: CGRect,
        corner: TriggerCorner,
        size: CGSize = defaultSize
    ) -> CGRect {
        switch corner {
        case .topLeft:
            CGRect(
                x: visibleFrame.minX + edgeInset,
                y: visibleFrame.maxY - edgeInset - size.height,
                width: size.width,
                height: size.height
            )
        case .topRight:
            CGRect(
                x: visibleFrame.maxX - edgeInset - size.width,
                y: visibleFrame.maxY - edgeInset - size.height,
                width: size.width,
                height: size.height
            )
        case .bottomLeft:
            CGRect(
                x: visibleFrame.minX + edgeInset,
                y: visibleFrame.minY + edgeInset,
                width: size.width,
                height: size.height
            )
        case .bottomRight:
            CGRect(
                x: visibleFrame.maxX - edgeInset - size.width,
                y: visibleFrame.minY + edgeInset,
                width: size.width,
                height: size.height
            )
        }
    }

    static func clampedFrame(_ frame: CGRect, inside visibleFrame: CGRect) -> CGRect {
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        let origin = CGPoint(
            x: min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width),
            y: min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height)
        )
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    static func returnTarget(
        for panelFrame: CGRect,
        screens: [PanelScreenGeometry],
        currentScreenID: UInt32?,
        currentCorner: TriggerCorner
    ) -> PanelReturnTarget? {
        guard let screen = owningScreen(
            for: panelFrame,
            screens: screens,
            currentScreenID: currentScreenID
        ) else {
            return nil
        }

        let panelCenter = CGPoint(x: panelFrame.midX, y: panelFrame.midY)
        let corner = nearestCorner(
            to: panelCenter,
            in: screen.frame,
            currentCorner: currentCorner
        )
        return PanelReturnTarget(
            screenID: screen.id,
            corner: corner,
            frame: frame(
                inside: screen.visibleFrame,
                corner: corner,
                size: panelFrame.size
            )
        )
    }

    private static func owningScreen(
        for panelFrame: CGRect,
        screens: [PanelScreenGeometry],
        currentScreenID: UInt32?
    ) -> PanelScreenGeometry? {
        guard !screens.isEmpty else { return nil }

        let intersections = screens.map { screen in
            let intersection = panelFrame.intersection(screen.frame)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            return (screen: screen, value: area)
        }
        let maximumArea = intersections.map(\.value).max() ?? 0
        if maximumArea > 0 {
            return preferredScreen(
                among: intersections
                    .filter { $0.value == maximumArea }
                    .map(\.screen),
                currentScreenID: currentScreenID
            )
        }

        let center = CGPoint(x: panelFrame.midX, y: panelFrame.midY)
        let distances = screens.map { screen in
            (screen: screen, value: squaredDistance(from: center, to: screen.frame))
        }
        let minimumDistance = distances.map(\.value).min() ?? 0
        return preferredScreen(
            among: distances
                .filter { $0.value == minimumDistance }
                .map(\.screen),
            currentScreenID: currentScreenID
        )
    }

    private static func preferredScreen(
        among screens: [PanelScreenGeometry],
        currentScreenID: UInt32?
    ) -> PanelScreenGeometry? {
        if let currentScreenID,
           let current = screens.first(where: { $0.id == currentScreenID }) {
            return current
        }
        return screens.min { $0.id < $1.id }
    }

    private static func nearestCorner(
        to point: CGPoint,
        in screenFrame: CGRect,
        currentCorner: TriggerCorner
    ) -> TriggerCorner {
        let distances = cornerOrder.map { corner in
            (corner: corner, value: squaredDistance(
                from: point,
                to: cornerPoint(for: corner, in: screenFrame)
            ))
        }
        let minimumDistance = distances.map(\.value).min() ?? 0
        let nearestCorners = distances
            .filter { $0.value == minimumDistance }
            .map(\.corner)

        if nearestCorners.contains(currentCorner) {
            return currentCorner
        }
        return nearestCorners.first ?? .topLeft
    }

    private static func cornerPoint(
        for corner: TriggerCorner,
        in frame: CGRect
    ) -> CGPoint {
        switch corner {
        case .topLeft:
            CGPoint(x: frame.minX, y: frame.maxY)
        case .topRight:
            CGPoint(x: frame.maxX, y: frame.maxY)
        case .bottomLeft:
            CGPoint(x: frame.minX, y: frame.minY)
        case .bottomRight:
            CGPoint(x: frame.maxX, y: frame.minY)
        }
    }

    private static func squaredDistance(from point: CGPoint, to other: CGPoint) -> CGFloat {
        let deltaX = point.x - other.x
        let deltaY = point.y - other.y
        return deltaX * deltaX + deltaY * deltaY
    }

    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let nearestX = min(max(point.x, rect.minX), rect.maxX)
        let nearestY = min(max(point.y, rect.minY), rect.maxY)
        return squaredDistance(from: point, to: CGPoint(x: nearestX, y: nearestY))
    }
}
