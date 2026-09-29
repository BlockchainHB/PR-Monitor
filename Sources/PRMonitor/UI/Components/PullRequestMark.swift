import SwiftUI

/// The familiar pull request mark: a branch with two nodes, and a second branch arcing back with an
/// arrow. One definition serves the menu bar icon (via `cgPath`) and in-app artwork (as a `Shape`).
///
/// Geometry is authored on a 16 × 16 grid with a 1.5pt stroke, matching the optical weight of
/// system menu bar symbols, and scales uniformly to any size.
struct PullRequestMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 16
        var path = Path()
        let r: CGFloat = 1.9

        // Left branch: two nodes joined by a line.
        path.addEllipse(in: CGRect(x: 3.5 - r, y: 3.4 - r, width: r * 2, height: r * 2))
        path.addEllipse(in: CGRect(x: 3.5 - r, y: 12.8 - r, width: r * 2, height: r * 2))
        path.move(to: CGPoint(x: 3.5, y: 5.3))
        path.addLine(to: CGPoint(x: 3.5, y: 10.9))

        // Right branch: a node rising and curving back toward the left branch, ending in an arrow.
        path.addEllipse(in: CGRect(x: 11.5 - r, y: 12.8 - r, width: r * 2, height: r * 2))
        path.move(to: CGPoint(x: 11.5, y: 10.9))
        path.addLine(to: CGPoint(x: 11.5, y: 5.8))
        path.addCurve(to: CGPoint(x: 9.2, y: 3.4), control1: CGPoint(x: 11.5, y: 4.4), control2: CGPoint(x: 10.6, y: 3.4))
        path.addLine(to: CGPoint(x: 7.2, y: 3.4))
        path.move(to: CGPoint(x: 8.9, y: 1.7))
        path.addLine(to: CGPoint(x: 7.2, y: 3.4))
        path.addLine(to: CGPoint(x: 8.9, y: 5.1))

        let offset = CGPoint(x: rect.midX - 8 * scale, y: rect.midY - 8 * scale)
        return path
            .applying(CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: offset.x, y: offset.y)))
            .strokedPath(StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round, lineJoin: .round))
    }
}
