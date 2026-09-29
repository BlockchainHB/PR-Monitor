import SwiftUI

/// Loading placeholders ("bones") that mirror the geometry of the content they stand in for, so
/// nothing shifts when real data arrives, and the wait reads as "content is coming" rather than
/// an indeterminate spinner.
struct Bone: View {
    var width: CGFloat? = nil
    var height: CGFloat = 9

    var body: some View {
        Capsule()
            .fill(.primary.opacity(0.09))
            .frame(width: width, height: height)
    }
}

struct BoneCircle: View {
    var size: CGFloat

    var body: some View {
        Circle()
            .fill(.primary.opacity(0.09))
            .frame(width: size, height: size)
    }
}

extension View {
    /// A slow, gentle breathing pulse for skeletons. Static when Reduce Motion is on.
    func skeletonPulse() -> some View {
        modifier(SkeletonPulse())
    }
}

private struct SkeletonPulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(isDimmed ? 0.5 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { isDimmed = true }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading")
    }
}

// MARK: - Panel

/// Stands in for the pull request list on first load. Uses the same insets, glyph size, and line
/// heights as `PullRequestRow`.
struct PullRequestListSkeleton: View {
    private let rows: [(title: CGFloat, detail: CGFloat)] = [(210, 150), (170, 180), (230, 130), (150, 160)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Bone(width: 110, height: 8)
                .padding(.horizontal, Metrics.edgeInset)
                .padding(.top, 13)
                .padding(.bottom, 7)
            ForEach(rows.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 10) {
                    BoneCircle(size: 20)
                    VStack(alignment: .leading, spacing: 7) {
                        Bone(width: rows[index].title, height: 10)
                        Bone(width: rows[index].detail, height: 8)
                    }
                    .padding(.top, 3)
                }
                .padding(.leading, Metrics.edgeInset)
                .padding(.vertical, 8)
            }
        }
        .padding(.bottom, Metrics.highlightInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .skeletonPulse()
    }
}

// MARK: - Settings

/// Stands in for a list of repositories or accounts: a circle and two lines per row.
struct ListRowSkeleton: View {
    var count = 6
    var circleSize: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(0..<count, id: \.self) { index in
                HStack(spacing: 10) {
                    BoneCircle(size: circleSize)
                    VStack(alignment: .leading, spacing: 6) {
                        Bone(width: [180, 140, 210, 160, 120, 190][index % 6], height: 10)
                        Bone(width: [240, 200, 170, 220, 180, 150][index % 6], height: 8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .skeletonPulse()
    }
}
