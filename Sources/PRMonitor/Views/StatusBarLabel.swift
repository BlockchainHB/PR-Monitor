import SwiftUI

struct StatusBarLabel: View {
    let status: AppState.OverallStatus

    private var color: Color {
        switch status {
        case .needsAuth:
            return .gray
        case .idle:
            return .gray
        case .running:
            return .blue
        case .waiting:
            return .yellow
        case .done:
            return .green
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 14, weight: .medium))
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .offset(x: 3, y: 3)
        }
    }
}
