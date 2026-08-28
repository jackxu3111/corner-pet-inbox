import AppKit

@MainActor
final class CornerPanel: NSPanel {
    var onTogglePin: (() -> Void)?
    var onFind: (() -> Bool)?

    private(set) var isPinned = false

    var contentSize: CGSize {
        get { contentView?.frame.size ?? frame.size }
        set { setContentSize(newValue) }
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        configure()
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        isFloatingPanel = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isMovable = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    func setPinned(_ pinned: Bool) {
        isPinned = pinned

        if pinned {
            styleMask.insert(.resizable)
            isMovable = true
            isMovableByWindowBackground = false
            contentMinSize = PinnedPanelSizeStore.minimumSize
            contentMaxSize = PinnedPanelSizeStore.maximumSize
        } else {
            styleMask.remove(.resizable)
            isMovable = false
            isMovableByWindowBackground = false
            contentMinSize = .zero
            contentMaxSize = CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])

        if event.keyCode == 35,
           modifiers == [.command, .shift] {
            onTogglePin?()
            return true
        }

        if event.charactersIgnoringModifiers?.lowercased() == "f",
           modifiers == [.command],
           onFind?() == true {
            return true
        }

        if event.charactersIgnoringModifiers == ",",
           modifiers == [.command] {
            NSApp.activate()
            DispatchQueue.main.async {
                _ = NSApp.mainMenu?.performKeyEquivalent(with: event)
            }
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown,
              event.modifierFlags.contains(.command),
              performKeyEquivalent(with: event) else {
            super.sendEvent(event)
            return
        }
    }
}
