import AppKit
import SwiftUI

/// A GitHub avatar that never flashes blank: a pulsing bone while the photo loads, then a
/// crossfade to it. The user's initial is the fallback if there's no photo. Loaded images are
/// cached for the session, so the sidebar and the Account pane show the same avatar instantly.
struct Avatar: View {
    let login: String?
    var size: CGFloat = 36

    private enum Phase { case loading, loaded(NSImage), fallback }
    @State private var phase: Phase = .loading

    var body: some View {
        ZStack {
            switch phase {
            case .loading:
                BoneCircle(size: size).skeletonPulse().transition(.opacity)
            case let .loaded(image):
                Image(nsImage: image).resizable().scaledToFill().transition(.opacity)
            case .fallback:
                monogram.transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        .accessibilityHidden(true)
        .task(id: login) { await load() }
    }

    private var monogram: some View {
        Circle()
            .fill(Color.accentColor.gradient)
            .overlay {
                if let initial = login?.first {
                    Text(String(initial).uppercased())
                        .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
    }

    private func load() async {
        guard let login else { phase = .fallback; return }
        if let cached = AvatarCache.shared[login] {
            phase = .loaded(cached)
            return
        }
        phase = .loading
        guard let url = URL(string: "https://github.com/\(login).png?size=\(Int(size * 3))"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let loaded = NSImage(data: data) else {
            withAnimation(Motion.crossfade) { phase = .fallback }
            return
        }
        AvatarCache.shared[login] = loaded
        withAnimation(Motion.crossfade) { phase = .loaded(loaded) }
    }
}

@MainActor
private final class AvatarCache {
    static let shared = AvatarCache()
    private var images: [String: NSImage] = [:]

    subscript(login: String) -> NSImage? {
        get { images[login.lowercased()] }
        set { images[login.lowercased()] = newValue }
    }
}
