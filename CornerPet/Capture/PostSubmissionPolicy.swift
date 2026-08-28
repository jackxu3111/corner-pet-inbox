enum PostSubmissionDecision: Equatable {
    case keepOpenAndRefocus
    case closePanel
}

struct PostSubmissionPolicy {
    static func decide(
        pointerInside: Bool,
        isPinned: Bool
    ) -> PostSubmissionDecision {
        isPinned || pointerInside ? .keepOpenAndRefocus : .closePanel
    }
}
