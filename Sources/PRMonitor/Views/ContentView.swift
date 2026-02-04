import SwiftUI
import AppKit
import Foundation

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var expandedPRs: Set<String> = []
    @State private var hoveredPRs: Set<String> = []
    @State private var hoveredMenuItem: String? = nil
    @State private var listContentHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 48
    @State private var footerHeight: CGFloat = 96
    @State private var errorHeight: CGFloat = 0

    private let maxPopoverHeight: CGFloat
    private let onSizeChange: ((CGSize) -> Void)?
    private let preferredWidth: CGFloat = 520

    init(maxPopoverHeight: CGFloat = 760, onSizeChange: ((CGSize) -> Void)? = nil) {
        self.maxPopoverHeight = maxPopoverHeight
        self.onSizeChange = onSizeChange
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            if let error = appState.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: ErrorHeightKey.self, value: proxy.size.height)
                        }
                    )
            }
            Divider()
            content
            footer
        }
        .padding(12)
        .frame(width: preferredWidth, height: windowHeight)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: RootSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(RootSizeKey.self) { size in
            onSizeChange?(size)
        }
        .onPreferenceChange(ErrorHeightKey.self) { height in
            errorHeight = height
        }
        .onChange(of: appState.errorMessage) { value in
            if value == nil { errorHeight = 0 }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("PR Monitor")
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(statusText)
                    if let detail = statusDetailText {
                        Text("• \(detail)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: HeaderHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(HeaderHeightKey.self) { height in
            headerHeight = height
        }
    }

    @ViewBuilder
    private var content: some View {
        if !appState.authStore.isSignedIn {
            unavailableView(
                title: "Sign in to GitHub",
                systemImage: "person.crop.circle.badge.xmark",
                message: "Connect GitHub to start monitoring."
            )
        } else if appState.repoSections.isEmpty {
            unavailableView(
                title: "No Open Pull Requests",
                systemImage: "tray",
                message: "No open PRs in tracked repos."
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(appState.repoSections) { section in
                        repoSection(section)
                    }
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ListContentHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            .onPreferenceChange(ListContentHeightKey.self) { height in
                listContentHeight = height
            }
            .frame(height: listHeight)
        }
    }

    private func repoSection(_ section: RepoSection) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(section.prs) { pr in
                    prRow(pr)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(section.fullName)
                    .font(.caption.weight(.semibold))
                Text("• \(section.prs.count) PR\(section.prs.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func prRow(_ pr: PRItem) -> some View {
        let isExpanded = expandedPRs.contains(prKey(pr))
        let isHovered = hoveredPRs.contains(prKey(pr))
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Button {
                        toggleExpanded(pr)
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Hide checks" : "Show checks")

                    Text("#\(pr.number)")
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                    Text(pr.title)
                        .font(.callout)
                        .lineLimit(1)

                    Spacer(minLength: 12)

                    StatusPill(status: prStatus(pr))
                }

                Text("by \(pr.author)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    if pr.agents.isEmpty {
                        Text("No checks configured for this repo.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pr.agents) { agent in
                            agentRow(agent)
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isHovered ? Color.primary.opacity(0.12) : Color.clear, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            openPR(pr.url)
        }
        .onHover { hovering in
            let key = prKey(pr)
            if hovering {
                hoveredPRs.insert(key)
                NSCursor.pointingHand.push()
            } else {
                hoveredPRs.remove(key)
                NSCursor.pop()
            }
        }
        .contextMenu {
            Button("Open Pull Request") {
                openPR(pr.url)
            }
            Button("Open Checks") {
                openPR(checksURL(for: pr))
            }
            Button("Copy URL") {
                copyToPasteboard(pr.url.absoluteString)
            }
            Button("Copy Title") {
                copyToPasteboard("#\(pr.number) \(pr.title)")
            }
        }
    }

    private func agentRow(_ agent: AgentRun) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(agent.status.color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.displayName)
                    .font(.caption)
            }
            Spacer()
            Text(agentStatusText(agent))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("\(agent.displayName), \(agentStatusText(agent))")
    }

    private func prStatus(_ pr: PRItem) -> AgentRunStatus {
        if pr.agents.contains(where: { $0.status == .running }) { return .running }
        if pr.agents.contains(where: { $0.status == .waitingForComment || $0.status == .notFound }) { return .waitingForComment }
        return .done
    }

    private func agentStatusText(_ agent: AgentRun) -> String {
        switch agent.status {
        case .running:
            return "Running"
        case .waitingForComment:
            return agent.commentCount > 0 ? "Needs review" : "Waiting"
        case .done:
            return conclusionText(agent) ?? "Done"
        case .notFound:
            return "No check yet"
        }
    }

    private func emptyState(text: String) -> some View {
        VStack(spacing: 8) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }

    private var settingsAction: some View {
        Group {
            if #available(macOS 14.0, *) {
                SettingsLink(label: {
                    Text("Open Settings")
                })
            } else {
                Button("Open Settings") {
                    openSettings()
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Divider()
            VStack(spacing: 0) {
                Button {
                    appState.refreshNow()
                } label: {
                    menuRowLabel(
                        id: "refresh",
                        title: appState.isRefreshing ? "Refreshing" : "Refresh",
                        systemImage: "arrow.clockwise",
                        trailing: appState.isRefreshing ? .progress : nil
                    )
                }
                .buttonStyle(.plain)
                .disabled(appState.isRefreshing)
                .keyboardShortcut("r")
                .help("Refresh now")

                settingsFooterAction

                Button {
                    NSApp.terminate(nil)
                } label: {
                    menuRowLabel(id: "quit", title: "Quit PR Monitor", systemImage: "power")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.bottom, 6)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: FooterHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(FooterHeightKey.self) { height in
            footerHeight = height
        }
    }

    private var settingsFooterAction: some View {
        Group {
            if #available(macOS 14.0, *) {
                SettingsLink(label: {
                    menuRowLabel(id: "settings", title: "Settings…", systemImage: "gearshape")
                })
            } else {
                Button {
                    openSettings()
                } label: {
                    menuRowLabel(id: "settings", title: "Settings…", systemImage: "gearshape")
                }
            }
        }
        .buttonStyle(.plain)
        .help("Open Settings")
    }

    private enum MenuRowTrailing {
        case progress
    }

    @ViewBuilder
    private func menuRowLabel(
        id: String,
        title: String,
        systemImage: String? = nil,
        isEnabled: Bool = true,
        trailing: MenuRowTrailing? = nil
    ) -> some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.secondary)
            }
            Text(title)
            Spacer()
            if trailing == .progress {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            hoveredMenuItem == id ? Color.primary.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
        )
        .opacity(isEnabled ? 1 : 0.5)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: hoveredMenuItem == id)
        .onHover { hovering in
            guard isEnabled else { return }
            hoveredMenuItem = hovering ? id : nil
        }
    }

    private func prKey(_ pr: PRItem) -> String {
        "\(pr.repoFullName)#\(pr.number)"
    }

    private func toggleExpanded(_ pr: PRItem) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            let key = prKey(pr)
            if expandedPRs.contains(key) {
                expandedPRs.remove(key)
            } else {
                expandedPRs.insert(key)
            }
        }
    }


    private func checksURL(for pr: PRItem) -> URL {
        pr.url.appendingPathComponent("checks")
    }

    private func conclusionText(_ agent: AgentRun) -> String? {
        guard agent.status == .done else { return nil }
        guard let conclusion = agent.checkConclusion, !conclusion.isEmpty else { return nil }
        return conclusion.replacingOccurrences(of: "_", with: " ").capitalized
    }


    private func openSettings() {
        NSApp.sendAction(Selector("showSettingsWindow:"), to: nil, from: nil)
    }

    private func openPR(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private var statusText: String {
        if let login = appState.viewerLogin {
            return "Signed in as \(login)"
        }
        return appState.authStore.isSignedIn ? "Connected" : "Sign in required"
    }

    private var statusDetailText: String? {
        if appState.isRefreshing {
            return "Refreshing…"
        }
        guard let last = appState.lastRefresh else { return nil }
        return "Updated \(relativeTime(from: last))"
    }

    private var totalPRCount: Int {
        appState.repoSections.reduce(0) { $0 + $1.prs.count }
    }

    private var listHeight: CGFloat {
        guard appState.authStore.isSignedIn, totalPRCount > 0 else { return 0 }
        let maxList = maxListHeight
        let content = listContentHeight > 0 ? listContentHeight : maxList
        return min(content, maxList)
    }

    private var windowHeight: CGFloat {
        guard appState.authStore.isSignedIn, totalPRCount > 0 else { return 260 }
        return min(maxPopoverHeight, chromeHeight + listHeight)
    }

    private var chromeHeight: CGFloat {
        let padding: CGFloat = 24
        let dividerHeight: CGFloat = 1
        let elements = 3 + (appState.errorMessage == nil ? 0 : 1)
        let gaps = max(0, elements - 1)
        let spacing = CGFloat(gaps) * 12
        return headerHeight + footerHeight + errorHeight + padding + dividerHeight + spacing
    }

    private var maxListHeight: CGFloat {
        let available = maxPopoverHeight - chromeHeight
        return max(120, available)
    }

    private func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private func unavailableView(title: String, systemImage: String, message: String) -> some View {
        if #available(macOS 14.0, *) {
            ContentUnavailableView(label: {
                Label(title, systemImage: systemImage)
            }, description: {
                Text(message)
            }, actions: {
                settingsAction
            })
        } else {
            emptyState(text: message)
        }
    }
}

private struct StatusPill: View {
    let status: AgentRunStatus

    private var text: String {
        switch status {
        case .running:
            return "Running"
        case .waitingForComment:
            return "Waiting"
        case .done:
            return "Ready"
        case .notFound:
            return "Pending"
        }
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.2), in: Capsule())
            .foregroundStyle(status.color)
            .accessibilityLabel("Status")
            .accessibilityValue(text)
    }
}

extension AgentRunStatus {
    var color: Color {
        switch self {
        case .running: return .blue
        case .waitingForComment: return .orange
        case .notFound: return .gray
        case .done: return .green
        }
    }
}

private struct RootSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private struct HeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

private struct FooterHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

private struct ErrorHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

private struct ListContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}
