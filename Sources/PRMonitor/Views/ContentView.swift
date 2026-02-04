import SwiftUI
import AppKit
import Foundation

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var expandedPRs: Set<Int> = []

    var body: some View {
        VStack(spacing: 12) {
            header
            if let error = appState.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Divider()
            content
        }
        .padding(12)
        .frame(minWidth: 360, idealWidth: 420)
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
            ControlGroup {
                Button {
                    appState.refreshNow()
                } label: {
                    if appState.isRefreshing {
                        Label {
                            Text("Refreshing")
                        } icon: {
                            ProgressView()
                        }
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .help("Refresh now")
                .disabled(appState.isRefreshing)
                settingsButton
            }
            .controlGroupStyle(.automatic)
            .labelStyle(.iconOnly)
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
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(appState.repoSections) { section in
                        repoSection(section)
                    }
                }
            }
            .frame(maxHeight: 520)
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
            Text(section.fullName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func prRow(_ pr: PRItem) -> some View {
        DisclosureGroup(isExpanded: isExpandedBinding(for: pr.id)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Link(destination: pr.url) {
                        Label("Open PR", systemImage: "arrow.up.right.square")
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                    Button {
                        copyToPasteboard(pr.url.absoluteString)
                    } label: {
                        Label("Copy URL", systemImage: "link")
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
                ForEach(pr.agents) { agent in
                    agentRow(pr: pr, agent: agent)
                }
            }
            .padding(.leading, 16)
        } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("#\(pr.number)")
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                        Text(pr.title)
                            .font(.callout)
                            .lineLimit(1)
                    }
                    Text("by \(pr.author) • Updated \(relativeTime(from: pr.updatedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(status: prStatus(pr))
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contextMenu {
            Button("Open Pull Request") {
                openPR(pr.url)
            }
            Button("Copy URL") {
                copyToPasteboard(pr.url.absoluteString)
            }
            Button("Copy Title") {
                copyToPasteboard("#\(pr.number) \(pr.title)")
            }
        }
    }

    private func agentRow(pr: PRItem, agent: AgentRun) -> some View {
        Link(destination: pr.url) {
            HStack {
                Circle()
                    .fill(agentColor(agent.status))
                    .frame(width: 8, height: 8)
                Text(agent.displayName)
                    .font(.caption)
                Spacer()
                Text(agentStatusText(agent))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(agent.displayName), \(agentStatusText(agent))")
        .accessibilityHint("Opens pull request in browser")
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
            return "Waiting for comment"
        case .done:
            return "\(agent.commentCount) comment\(agent.commentCount == 1 ? "" : "s")"
        case .notFound:
            return "No check yet"
        }
    }

    private func agentColor(_ status: AgentRunStatus) -> Color {
        switch status {
        case .running:
            return .blue
        case .waitingForComment:
            return .orange
        case .notFound:
            return .gray
        case .done:
            return .green
        }
    }

    private func emptyState(text: String) -> some View {
        VStack(spacing: 8) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    @ViewBuilder
    private var settingsButton: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                Label("Settings", systemImage: "gear")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        } else {
            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gear")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
    }

    private var settingsAction: some View {
        Group {
            if #available(macOS 14.0, *) {
                SettingsLink("Open Settings")
            } else {
                Button("Open Settings") {
                    openSettings()
                }
            }
        }
    }

    private func isExpandedBinding(for id: Int) -> Binding<Bool> {
        Binding(
            get: { expandedPRs.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedPRs.insert(id)
                } else {
                    expandedPRs.remove(id)
                }
            }
        )
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

    private func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private func unavailableView(title: String, systemImage: String, message: String) -> some View {
        if #available(macOS 14.0, *) {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(message)
            } actions: {
                settingsAction
            }
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

    private var color: Color {
        switch status {
        case .running:
            return .blue
        case .waitingForComment:
            return .orange
        case .notFound:
            return .gray
        case .done:
            return .green
        }
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
            .accessibilityLabel("Status")
            .accessibilityValue(text)
    }
}
