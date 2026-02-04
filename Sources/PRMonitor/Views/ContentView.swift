import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var expandedPRs: Set<String> = []

    var body: some View {
        VStack(spacing: 12) {
            header
            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            Divider()
            content
        }
        .padding(12)
        .frame(width: 420)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("PR Monitor")
                    .font(.headline)
                if let login = appState.viewerLogin {
                    Text("Signed in as \(login)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(appState.authStore.isSignedIn ? "Connected" : "Sign in required")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button {
                appState.refreshNow()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
            settingsButton
        }
    }

    @ViewBuilder
    private var content: some View {
        if !appState.authStore.isSignedIn {
            emptyState(text: "Connect GitHub to start monitoring.")
        } else if appState.repoSections.isEmpty {
            emptyState(text: "No open PRs in tracked repos.")
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
        VStack(alignment: .leading, spacing: 6) {
            Text(section.fullName)
                .font(.subheadline)
                .foregroundColor(.secondary)
            ForEach(section.prs) { pr in
                prRow(pr)
            }
        }
    }

    private func prRow(_ pr: PRItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: expandedPRs.contains(prKey(pr)) ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("#\(pr.number) \(pr.title)")
                        .font(.callout)
                        .lineLimit(1)
                    Text("by \(pr.author)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                StatusPill(status: prStatus(pr))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                togglePR(pr)
            }

            if expandedPRs.contains(prKey(pr)) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(pr.agents) { agent in
                        agentRow(pr: pr, agent: agent)
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func agentRow(pr: PRItem, agent: AgentRun) -> some View {
        Button {
            NSWorkspace.shared.open(pr.url)
        } label: {
            HStack {
                Circle()
                    .fill(agentColor(agent.status))
                    .frame(width: 8, height: 8)
                Text(agent.displayName)
                    .font(.caption)
                Spacer()
                Text(agentStatusText(agent))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
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
        case .waitingForComment, .notFound:
            return .yellow
        case .done:
            return .green
        }
    }

    private func emptyState(text: String) -> some View {
        VStack(spacing: 8) {
            Text(text)
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func togglePR(_ pr: PRItem) {
        let key = prKey(pr)
        if expandedPRs.contains(key) {
            expandedPRs.remove(key)
        } else {
            expandedPRs.insert(key)
        }
    }

    private func prKey(_ pr: PRItem) -> String {
        "\(pr.repoFullName)#\(pr.number)"
    }

    @ViewBuilder
    private var settingsButton: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                Label("Settings", systemImage: "gear")
            }
            .buttonStyle(.borderless)
        } else {
            Button {
                NSApp.sendAction(Selector("showSettingsWindow:"), to: nil, from: nil)
            } label: {
                Label("Settings", systemImage: "gear")
            }
            .buttonStyle(.borderless)
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
        case .waitingForComment, .notFound:
            return .yellow
        case .done:
            return .green
        }
    }

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(8)
    }
}
