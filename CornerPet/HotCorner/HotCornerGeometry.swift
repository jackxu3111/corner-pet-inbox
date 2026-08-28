import CoreGraphics

struct HotCornerGeometry {
    private static let armLength: CGFloat = 86
    private static let thickness: CGFloat = 20

    static func regions(frame: CGRect, corner: TriggerCorner) -> [CGRect] {
        switch corner {
        case .topLeft:
            return [
                CGRect(x: frame.minX, y: frame.maxY - thickness, width: armLength, height: thickness),
                CGRect(x: frame.minX, y: frame.maxY - armLength, width: thickness, height: armLength)
            ]
        case .topRight:
            return [
                CGRect(x: frame.maxX - armLength, y: frame.maxY - thickness, width: armLength, height: thickness),
                CGRect(x: frame.maxX - thickness, y: frame.maxY - armLength, width: thickness, height: armLength)
            ]
        case .bottomLeft:
            return [
                CGRect(x: frame.minX, y: frame.minY, width: armLength, height: thickness),
                CGRect(x: frame.minX, y: frame.minY, width: thickness, height: armLength)
            ]
        case .bottomRight:
            return [
                CGRect(x: frame.maxX - armLength, y: frame.minY, width: armLength, height: thickness),
                CGRect(x: frame.maxX - thickness, y: frame.minY, width: thickness, height: armLength)
            ]
        }
    }

    static func contains(point: CGPoint, frame: CGRect, corner: TriggerCorner) -> Bool {
        for region in regions(frame: frame, corner: corner) {
            if point.x >= region.minX && point.x <= region.maxX
                && point.y >= region.minY && point.y <= region.maxY {
                return true
            }
        }

        return false
    }
}
