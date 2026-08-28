enum CaptureKeyboardAction: Equatable {
    case submit
    case insertNewline
    case escape
    case passThrough
}

struct CaptureKeyboardPolicy {
    static func action(
        keyCode: UInt16,
        isShiftPressed: Bool
    ) -> CaptureKeyboardAction {
        switch keyCode {
        case 36, 76:
            isShiftPressed ? .insertNewline : .submit
        case 53:
            .escape
        default:
            .passThrough
        }
    }
}
