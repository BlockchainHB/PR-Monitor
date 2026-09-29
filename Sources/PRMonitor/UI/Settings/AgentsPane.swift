import SwiftUI

struct AgentsPane: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Monitor.self) private var monitor
    @State private var editing: Agent?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Track") {
                ModeOption(
                    title: "Automatic",
                    detail: "Every CI system, deployment, and AI reviewer that reports on a pull request. Jobs from the same integration are grouped.",
                    isSelected: settings.agentMode == .automatic
                ) { settings.agentMode = .automatic }
                ModeOption(
                    title: "Only agents I choose",
                    detail: "Only the agents you add count toward a pull request's status.",
                    isSelected: settings.agentMode == .custom
                ) { settings.agentMode = .custom }
            }

            switch settings.agentMode {
            case .automatic:
                detectedSection
            case .custom:
                configuredSection
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { agent in
            AgentEditor(agent: agent) { saved in
                if let index = settings.agents.firstIndex(where: { $0.id == saved.id }) {
                    settings.agents[index] = saved
                } else {
                    settings.agents.append(saved)
                }
            }
        }
    }

    // MARK: - Automatic

    @ViewBuilder
    private var detectedSection: some View {
        let detected = monitor.discoveredAgents
        Section {
            if detected.isEmpty {
                Text("Agents appear here once they report on an open pull request.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(detected) { agent in
                    AgentSummaryRow(agent: agent)
                }
            }
        } header: {
            Text("Seen on Your Pull Requests")
        }
    }

    // MARK: - Custom

    @ViewBuilder
    private var configuredSection: some View {
        Section {
            if settings.agents.isEmpty {
                Text("Add the checks and reviewers you care about.")
                    .foregroundStyle(.secondary)
            }
            ForEach(settings.agents) { agent in
                HStack {
                    AgentSummaryRow(agent: agent)
                    Spacer()
                    Button("Edit") { editing = agent }
                        .buttonStyle(.borderless)
                    Button(role: .destructive) {
                        settings.agents.removeAll { $0.id == agent.id }
                    } label: {
                        Image(systemName: "minus.circle.fill").symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Remove \(agent.name)")
                }
            }
        } header: {
            HStack {
                Text("Agents")
                Spacer()
                addMenu
            }
        }
    }

    private var addMenu: some View {
        let configured = Set(settings.agents.map { Identity.normalize($0.login + $0.checkPattern) })
        let isNew: (Agent) -> Bool = { !configured.contains(Identity.normalize($0.login + $0.checkPattern)) }
        let suggestions = monitor.discoveredAgents.filter(isNew)
        let presets = Agent.presets.filter(isNew)

        return Menu {
            if !suggestions.isEmpty {
                Section("Seen on Your Pull Requests") {
                    ForEach(suggestions) { agent in
                        Button(agent.name) { settings.agents.append(Agent(name: agent.name, checkPattern: agent.checkPattern, login: agent.login)) }
                    }
                }
            }
            Section("Popular") {
                ForEach(presets, id: \.name) { agent in
                    Button(agent.name) { settings.agents.append(Agent(name: agent.name, checkPattern: agent.checkPattern, login: agent.login)) }
                }
            }
            Divider()
            Button("Custom Agent…") { editing = Agent(name: "") }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .fixedSize()
        .help("Add an agent")
        .accessibilityLabel("Add an agent")
    }
}

/// One choice in an iOS-style checkmark list: title and description, checkmark when selected.
private struct ModeOption: View {
    let title: String
    let detail: String
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

private struct AgentSummaryRow: View {
    let agent: Agent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(agent.name)
            Text(matchDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var matchDescription: String {
        var parts: [String] = []
        if !agent.checkPattern.trimmed.isEmpty { parts.append("Checks matching “\(agent.checkPattern)”") }
        if !agent.login.trimmed.isEmpty { parts.append("Reviews by @\(agent.login)") }
        return parts.joined(separator: " · ")
    }
}

private struct AgentEditor: View {
    @State var agent: Agent
    let save: (Agent) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $agent.name, prompt: Text("Cursor Bugbot"))
                } header: {
                    Text(agent.name.isEmpty ? "New Agent" : agent.name)
                }
                Section {
                    TextField("Check name contains", text: $agent.checkPattern, prompt: Text("cursor"))
                        .autocorrectionDisabled()
                    TextField("Bot account", text: $agent.login, prompt: Text("cursor"))
                        .autocorrectionDisabled()
                } footer: {
                    Text("Checks match by name, app, or status creator. The bot account matches review requests, reviews, and review threads. Fill in at least one.")
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save(agent)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!agent.isValid)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 420, height: 340)
    }
}
