import AppKit
import SwiftUI

/// The status item: a pull-request glyph with a small state badge, or an attention count.
///
/// By default the image is a template, so macOS tints it for light/dark menu bars and the selected
/// state, as the HIG asks. The badge's *shape* carries the state (filled dot = needs attention,
/// ring = in progress, dimmed glyph = not connected), so it reads without color. When there's a
/// count it replaces the dot, since the number already says "these need you". Everything, count
/// included, is drawn into one image so the spacing is exact.
struct MenuBarLabel: View {
    let summary: Monitor.Summary
    let count: Int
    let isColored: Bool

    var body: some View {
        Image(nsImage: StatusIcon.image(for: summary, count: count, isColored: isColored))
            .accessibilityLabel("PR Monitor")
            .accessibilityValue(StatusIcon.accessibilityValue(for: summary, count: count))
    }
}

enum StatusIcon {
    enum Badge {
        case none, dot(NSColor), ring(NSColor)
    }

    private static let glyphSize: CGFloat = 16
    private static let countSpacing: CGFloat = 4

    static func image(for summary: Monitor.Summary, count: Int = 0, isColored: Bool) -> NSImage {
        var (badge, isDimmed) = style(for: summary, isColored: isColored)
        let countText = count > 0 ? NSAttributedString(string: count.formatted(), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
        ]) : nil
        if countText != nil, case .dot = badge { badge = .none }

        let countWidth = countText.map { ceil($0.size().width) + countSpacing } ?? 0
        let badgeWidth: CGFloat = if case .none = badge { 0 } else { 5 }
        let size = NSSize(width: glyphSize + badgeWidth + countWidth, height: glyphSize)

        // Flipped so the mark's top-left-origin geometry draws upright.
        let image = NSImage(size: size, flipped: true) { _ in
            let ink: NSColor = isColored ? .labelColor : .black
            ink.withAlphaComponent(isDimmed ? 0.45 : 1).setFill()
            NSBezierPath(cgPath: PullRequestMark().path(in: CGRect(x: 0, y: 0, width: glyphSize, height: glyphSize)).cgPath).fill()

            switch badge {
            case .none:
                break
            case let .dot(color), let .ring(color):
                let rect = NSRect(x: glyphSize - 1.5, y: 5, width: 6, height: 6)
                // Knock out a gap around the badge so it separates cleanly from the glyph.
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                NSBezierPath(ovalIn: rect.insetBy(dx: -1.5, dy: -1.5)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                let fill = isColored ? color : .black
                if case .ring = badge {
                    let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
                    ring.lineWidth = 1.5
                    fill.setStroke()
                    ring.stroke()
                } else {
                    fill.setFill()
                    NSBezierPath(ovalIn: rect).fill()
                }
            }

            if let countText {
                let tint: NSColor = isColored ? countColor(for: summary) : .black
                let tinted = NSMutableAttributedString(attributedString: countText)
                tinted.addAttribute(.foregroundColor, value: tint, range: NSRange(location: 0, length: tinted.length))
                let textSize = tinted.size()
                tinted.draw(at: NSPoint(x: glyphSize + badgeWidth + countSpacing, y: (glyphSize - textSize.height) / 2))
            }
            return true
        }
        image.isTemplate = !isColored
        return image
    }

    private static func countColor(for summary: Monitor.Summary) -> NSColor {
        switch summary {
        case .failing: .systemRed
        case .needsReview: .systemOrange
        default: .labelColor
        }
    }

    /// In template mode a filled dot always means "act on this", so "ready" gets no badge there.
    private static func style(for summary: Monitor.Summary, isColored: Bool) -> (Badge, dimmed: Bool) {
        switch summary {
        case .signedOut, .needsRepositories, .unavailable: (.none, true)
        case .failing: (.dot(.systemRed), false)
        case .needsReview: (.dot(.systemOrange), false)
        case .running: (.ring(.systemBlue), false)
        case .ready: (isColored ? .dot(.systemGreen) : .none, false)
        case .idle: (.none, false)
        }
    }

    static func accessibilityValue(for summary: Monitor.Summary, count: Int) -> String {
        let state = switch summary {
        case .signedOut: "Not signed in"
        case .needsRepositories: "No repositories selected"
        case let .unavailable(error): error.localizedDescription
        case .failing: "Checks failing"
        case .needsReview: "Ready for review"
        case .running: "Agents running"
        case .ready: "All clear"
        case .idle: "No open pull requests"
        }
        return count > 0 ? "\(state), \(count) need attention" : state
    }
}
