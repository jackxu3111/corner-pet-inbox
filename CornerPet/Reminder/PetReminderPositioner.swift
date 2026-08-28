import CoreGraphics

struct PetReminderPlacement: Equatable, Sendable {
    let screenID: UInt32
    let frame: CGRect
}

enum PetReminderPositioner {
    static let preferredSize = CGSize(width: 240, height: 300)
    static let triggerClearance: CGFloat = 86

    static func placement(
        screens: [ScreenSnapshot],
        primaryDisplayID: UInt32?,
        pointerLocation: CGPoint,
        corner: TriggerCorner
    ) -> PetReminderPlacement? {
        guard let screen = screens.first(where: { $0.frame.contains(pointerLocation) })
            ?? primaryDisplayID.flatMap({ primaryID in
                screens.first { $0.id == primaryID }
            })
            ?? screens.first else {
            return nil
        }

        let width = min(preferredSize.width, screen.visibleFrame.width)
        let height = min(preferredSize.height, screen.visibleFrame.height)
        let x = switch corner {
        case .topLeft, .bottomLeft:
            screen.visibleFrame.minX
        case .topRight, .bottomRight:
            screen.visibleFrame.maxX - width
        }
        let proposedY = switch corner {
        case .topLeft, .topRight:
            min(
                screen.visibleFrame.maxY,
                screen.frame.maxY - triggerClearance
            ) - height
        case .bottomLeft, .bottomRight:
            max(
                screen.visibleFrame.minY,
                screen.frame.minY + triggerClearance
            )
        }
        let y = min(
            max(proposedY, screen.visibleFrame.minY),
            screen.visibleFrame.maxY - height
        )
        return PetReminderPlacement(
            screenID: screen.id,
            frame: CGRect(x: x, y: y, width: width, height: height)
        )
    }
}
