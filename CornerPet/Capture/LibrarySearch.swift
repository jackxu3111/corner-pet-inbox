import Foundation

enum LibrarySearchFocusRouting {
    static func requestFocus(_ setFocused: (Bool) -> Void) {
        setFocused(true)
    }
}

enum LibrarySearch {
    static func filter(
        _ items: [IdeaItemSnapshot],
        query: String
    ) -> [IdeaItemSnapshot] {
        guard !query.isEmpty else { return items }
        return items.filter { $0.text.localizedStandardContains(query) }
    }
}
