import SwiftUI

struct CapturePanelView: View {
    let captureViewModel: CaptureViewModel
    let inboxViewModel: InboxViewModel
    let favoritesViewModel: FavoritesViewModel?
    let archiveViewModel: ArchiveViewModel
    let shellViewModel: CaptureShellViewModel
    let pinStateBox: PanelPinStateBox?
    let pinState: () -> Bool
    let pinAvailable: Bool
    let onTogglePin: () -> Void
    let onPanelCommand: (CapturePanelCommand) -> Void

    @State private var measuredInputHeight = CaptureLayout.inputMinimumHeight
    @State private var focusRequest = 0

    init(
        captureViewModel: CaptureViewModel,
        inboxViewModel: InboxViewModel,
        favoritesViewModel: FavoritesViewModel? = nil,
        archiveViewModel: ArchiveViewModel,
        shellViewModel: CaptureShellViewModel,
        pinStateBox: PanelPinStateBox? = nil,
        pinState: @escaping () -> Bool,
        pinAvailable: Bool,
        onTogglePin: @escaping () -> Void,
        onPanelCommand: @escaping (CapturePanelCommand) -> Void
    ) {
        self.captureViewModel = captureViewModel
        self.inboxViewModel = inboxViewModel
        self.favoritesViewModel = favoritesViewModel
        self.archiveViewModel = archiveViewModel
        self.shellViewModel = shellViewModel
        self.pinStateBox = pinStateBox
        self.pinState = pinState
        self.pinAvailable = pinAvailable
        self.onTogglePin = onTogglePin
        self.onPanelCommand = onPanelCommand
    }

    var body: some View {
        ZStack(alignment: .top) {
            CornerPanelDragRegion(isEnabled: pinStateBox?.isPinned ?? pinState())
                .frame(maxWidth: .infinity)
                .frame(height: CaptureLayout.topDragRegionHeight)

            VStack(spacing: CaptureLayout.contentSpacing) {
                CaptureHeaderView(
                    isPinned: pinStateBox?.isPinned ?? pinState(),
                    pinAvailable: pinAvailable,
                    onTogglePin: onTogglePin
                )
                .frame(height: CaptureLayout.headerHeight)

                captureInput
                    .frame(height: measuredInputHeight)

                if let error = captureViewModel.saveError {
                    CaptureSaveErrorBanner(
                        error: error,
                        canRetry: captureViewModel.retryIntent != nil,
                        onRetry: captureViewModel.retryLastFailedOperation,
                        onDismiss: captureViewModel.dismissSaveError
                    )
                }

                destinationContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                CaptureNavigationBar(
                    selectedDestination: shellViewModel.selectedDestination,
                    onSelect: shellViewModel.select
                )
                .frame(height: CaptureLayout.navigationHeight)
            }
            .padding(CaptureLayout.outerPadding)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture.panel")
        .onAppear {
            captureViewModel.restoreDraft()
            inboxViewModel.load()
            consumePendingPanelCommand()
        }
        .onChange(of: captureViewModel.pendingPanelCommand) { _, command in
            guard command != nil else { return }
            consumePendingPanelCommand()
        }
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { captureViewModel.draftText },
            set: captureViewModel.draftDidChange
        )
    }

    private var captureInput: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(.background.opacity(0.58))

            if captureViewModel.draftText.isEmpty {
                Text("记下想法… / Capture a thought…")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            CaptureTextEditor(
                text: draftBinding,
                measuredHeight: $measuredInputHeight,
                focusRequest: focusRequest,
                onSubmit: { _ = captureViewModel.handleReturn(isShiftPressed: false) },
                onEscape: captureViewModel.handleEscape
            )
            .padding(.horizontal, 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var destinationContent: some View {
        switch shellViewModel.selectedDestination {
        case .inbox:
            InboxView(viewModel: inboxViewModel)
        case .favorites:
            if let favoritesViewModel {
                FavoritesView(viewModel: favoritesViewModel)
            } else {
                placeholder(destination: .favorites)
            }
        case .archive:
            ArchiveView(viewModel: archiveViewModel)
        case let destination:
            placeholder(destination: destination)
        }
    }

    private func placeholder(destination: CaptureDestination) -> some View {
        VStack(spacing: 10) {
            Image(systemName: destination.systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(destination.chineseTitle)
                .font(.headline)
            Text(destination.englishTitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("placeholder.\(destination.rawValue)")
    }

    private func consumePendingPanelCommand() {
        guard let command = captureViewModel.consumePanelCommand() else { return }

        switch command {
        case .focusInputAtEnd:
            focusRequest &+= 1
        case .close:
            onPanelCommand(command)
        }
    }
}

private struct CaptureSaveErrorBanner: View {
    let error: CaptureSaveError
    let canRetry: Bool
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(error.chineseMessage)
                Text(error.englishMessage)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            Spacer(minLength: 4)

            Button("重试 / Retry", action: onRetry)
                .disabled(!canRetry)
                .accessibilityIdentifier("capture.error.retry")
            Button("关闭 / Dismiss", action: onDismiss)
                .accessibilityIdentifier("capture.error.dismiss")
        }
        .padding(8)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture.error")
    }
}
