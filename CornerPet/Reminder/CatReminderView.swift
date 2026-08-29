import SwiftUI

struct CatReminderView: View {
    let corner: TriggerCorner
    let onOpenInbox: () -> Void
    let onSnooze: () -> Void
    let onDismissToday: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false

    var body: some View {
        VStack(spacing: 12) {
            CatIllustrationView(facesRight: corner.isLeftEdge)
                .frame(height: 86)
                .scaleEffect(reduceMotion || isPresented ? 1 : 0.9)
                .offset(y: reduceMotion || isPresented ? 0 : corner.isTopEdge ? -10 : 10)

            VStack(spacing: 3) {
                Text("该看看收件箱啦")
                    .font(.headline)
                Text("Time to check your inbox")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            Button("打开收件箱 / Open Inbox", action: onOpenInbox)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("reminder.openInbox")

            VStack(spacing: 6) {
                Button("10 分钟后提醒 / Remind in 10 Minutes", action: onSnooze)
                    .accessibilityIdentifier("reminder.snooze")
                Button("关闭 / 今天不再提醒 / Dismiss for Today", action: onDismissToday)
                    .accessibilityIdentifier("reminder.dismissToday")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: corner.edgeAlignment) {
            Capsule()
                .fill(.tint.opacity(0.7))
                .frame(width: 4, height: 34)
                .padding(8)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .opacity(isPresented ? 1 : 0)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reminder.panel")
        .onAppear {
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.16)) {
                    isPresented = true
                }
            } else {
                withAnimation(.spring(duration: 0.42, bounce: 0.3)) {
                    isPresented = true
                }
            }
        }
    }
}

private struct CatIllustrationView: View {
    let facesRight: Bool

    var body: some View {
        ZStack {
            CatTailShape()
                .stroke(Color.accentColor.opacity(0.7), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .frame(width: 70, height: 54)
                .offset(x: -34, y: 15)

            CatBodyView()
                .frame(width: 78, height: 62)
                .offset(y: 21)

            CatFaceView()
                .frame(width: 82, height: 72)
                .offset(x: 22, y: -8)
        }
        .scaleEffect(x: facesRight ? 1 : -1, y: 1)
        .accessibilityHidden(true)
    }
}

private struct CatFaceView: View {
    var body: some View {
        ZStack {
            HStack(spacing: 25) {
                CatEarShape()
                    .fill(Color.accentColor.opacity(0.78))
                CatEarShape()
                    .fill(Color.accentColor.opacity(0.78))
                    .scaleEffect(x: -1, y: 1)
            }
            .frame(height: 34)
            .offset(y: -25)

            Ellipse()
                .fill(.background)
                .overlay {
                    Ellipse().stroke(Color.accentColor.opacity(0.65), lineWidth: 3)
                }

            HStack(spacing: 21) {
                Circle().fill(.primary).frame(width: 6, height: 9)
                Circle().fill(.primary).frame(width: 6, height: 9)
            }
            .offset(y: -7)

            CatMuzzleShape()
                .stroke(.primary.opacity(0.75), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 25, height: 15)
                .offset(y: 12)
        }
    }
}

private struct CatBodyView: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.accentColor.opacity(0.72))
            HStack(spacing: 27) {
                Capsule().fill(.background).frame(width: 15, height: 29)
                Capsule().fill(.background).frame(width: 15, height: 29)
            }
            .offset(y: 7)
        }
    }
}

private struct CatEarShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct CatMuzzleShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.midY))
            path.addCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY),
                control1: CGPoint(x: rect.midX, y: rect.maxY),
                control2: CGPoint(x: rect.minX, y: rect.maxY)
            )
            path.move(to: CGPoint(x: rect.midX, y: rect.midY))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control1: CGPoint(x: rect.midX, y: rect.maxY),
                control2: CGPoint(x: rect.maxX, y: rect.maxY)
            )
        }
    }
}

private struct CatTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addCurve(
                to: CGPoint(x: rect.minX + 8, y: rect.minY + 8),
                control1: CGPoint(x: rect.midX, y: rect.maxY),
                control2: CGPoint(x: rect.minX, y: rect.midY)
            )
        }
    }
}

private extension TriggerCorner {
    var isLeftEdge: Bool {
        self == .topLeft || self == .bottomLeft
    }

    var isTopEdge: Bool {
        self == .topLeft || self == .topRight
    }

    var edgeAlignment: Alignment {
        switch self {
        case .topLeft, .bottomLeft: .leading
        case .topRight, .bottomRight: .trailing
        }
    }
}
