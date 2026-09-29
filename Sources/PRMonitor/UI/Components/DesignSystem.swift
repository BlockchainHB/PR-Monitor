import SwiftUI

/// Layout metrics shared by the menu bar panel. Values follow macOS menu geometry: highlights
/// inset 5pt from the panel edge, text aligned 14pt in, so rows read like native menu items.
enum Metrics {
    static let panelWidth: CGFloat = 360
    /// The panel's corner radius, published as a container shape so inner highlights can be
    /// concentric with it (inner radius = outer radius − inset).
    static let panelCornerRadius: CGFloat = 16
    static let edgeInset: CGFloat = 14
    static let highlightInset: CGFloat = 5
    static var rowPadding: CGFloat { edgeInset - highlightInset }
    static let minimumHighlightRadius: CGFloat = 8
    static let iconButtonSize: CGFloat = 28
}

/// Motion tokens. High-frequency feedback (hover) is instant; state changes are short and never bounce.
enum Motion {
    /// Expanding and collapsing rows: an interruptible spring with no bounce.
    static let disclosure = Animation.smooth(duration: 0.25)
    /// Rows moving or appearing after a refresh. Kept under 300ms, like all UI motion.
    static let content = Animation.smooth(duration: 0.25)
    /// Exits are shorter and softer than enters, so they don't compete for attention.
    static let exit = Animation.easeOut(duration: 0.15)
    /// Skeleton → content, image → image.
    static let crossfade = Animation.easeOut(duration: 0.2)
    static let press = Animation.snappy(duration: 0.12)
    static let pressedScale: CGFloat = 0.96
}

extension AnyTransition {
    /// Enter: fade in with a small drop. Exit: a quicker fade with a slight blur, and no travel.
    static var disclosure: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: -4)),
            removal: .opacity.combined(with: .blur(radius: 4)).animation(Motion.exit)
        )
    }
}

extension AnyTransition {
    static func blur(radius: CGFloat) -> AnyTransition {
        .modifier(active: BlurModifier(radius: radius), identity: BlurModifier(radius: 0))
    }
}

private struct BlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

// MARK: - Status semantics

extension PullRequestStatus {
    var tint: Color {
        switch self {
        case .failing: .red
        case .running: .blue
        case .needsReview: .orange
        case .ready: .green
        case .quiet: .gray
        }
    }

    /// Each status has a distinct glyph so it never relies on color alone.
    var symbol: String {
        switch self {
        case .failing: "xmark.circle.fill"
        case .running: "arrow.trianglehead.2.clockwise.rotate.90.circle.fill"
        case .needsReview: "exclamationmark.bubble.circle.fill"
        case .ready: "checkmark.circle.fill"
        case .quiet: "minus.circle.fill"
        }
    }

    var title: String {
        switch self {
        case .failing: "Failing"
        case .running: "In progress"
        case .needsReview: "Needs review"
        case .ready: "Ready"
        case .quiet: "No checks"
        }
    }
}

extension AgentReport.State {
    var tint: Color {
        switch self {
        case .running: .blue
        case .failed: .red
        case .needsReview: .orange
        case .passed: .green
        }
    }

    var symbol: String {
        switch self {
        case .running: "circle.dotted"
        case .failed: "xmark.circle.fill"
        case .needsReview: "exclamationmark.bubble.circle.fill"
        case .passed: "checkmark.circle.fill"
        }
    }
}

// MARK: - Shapes

/// A highlight shape that stays concentric with the panel's corners and falls back to a fixed
/// minimum radius away from them.
struct HighlightShape: Shape {
    func path(in rect: CGRect) -> Path {
        ConcentricRectangle(corners: .concentric(minimum: .fixed(Metrics.minimumHighlightRadius)), isUniform: true)
            .path(in: rect)
    }
}

// MARK: - Button styles

/// A menu-item-like row: an instant hover highlight, a slightly deeper fill while pressed.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration)
    }

    private struct RowBody: View {
        let configuration: Configuration
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .contentShape(HighlightShape())
                .background {
                    HighlightShape()
                        .fill(.primary.opacity(fillOpacity))
                }
                .onHover { isHovered = $0 && isEnabled }
        }

        private var fillOpacity: Double {
            if configuration.isPressed { return 0.12 }
            return isHovered ? 0.07 : 0
        }
    }
}

/// A borderless icon button for use inside the (already glass) panel. Glass-on-glass is avoided per
/// Apple's guidance, so this uses a circular hover fill and a subtle press scale instead.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconBody(configuration: configuration)
    }

    private struct IconBody: View {
        let configuration: Configuration
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.body)
                .foregroundStyle(isEnabled ? .secondary : .tertiary)
                .frame(width: Metrics.iconButtonSize, height: Metrics.iconButtonSize)
                .background(Circle().fill(.primary.opacity(isHovered && isEnabled ? 0.08 : 0)))
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed ? Motion.pressedScale : 1)
                .animation(Motion.press, value: configuration.isPressed)
                .onHover { isHovered = $0 }
        }
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var icon: IconButtonStyle { IconButtonStyle() }
}

// MARK: - Small components

/// A pull request's status as a soft, two-tone symbol: the glyph in the status color on a tinted
/// disc of the same hue, in the current SF Symbols style.
struct StatusGlyph: View {
    let status: PullRequestStatus
    var isDraft = false

    var body: some View {
        let tint: Color = isDraft ? .gray : status.tint
        Image(systemName: isDraft ? "pencil.circle.fill" : status.symbol)
            .font(.system(size: 19, weight: .medium))
            .symbolRenderingMode(.palette)
            .foregroundStyle(tint, tint.opacity(0.18))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 20, height: 20)
            .animation(.easeOut(duration: 0.2), value: status)
            .accessibilityHidden(true)
    }
}

/// The smaller companion used for individual agents.
struct AgentGlyph: View {
    let state: AgentReport.State

    var body: some View {
        Image(systemName: state.symbol)
            .font(.system(size: 12, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(state.tint, state.tint.opacity(0.18))
            .frame(width: 14)
            .accessibilityHidden(true)
    }
}

// MARK: - Formatting

extension Date {
    /// A compact age like "now", "4m", "2h" or "3d", sized for dense rows.
    func compactAge(relativeTo now: Date = .now) -> String {
        let minutes = Int(max(0, now.timeIntervalSince(self)) / 60)
        switch minutes {
        case ..<1: return "now"
        case ..<60: return "\(minutes)m"
        case ..<1440: return "\(minutes / 60)h"
        case ..<10080: return "\(minutes / 1440)d"
        default: return "\(minutes / 10080)w"
        }
    }
}
