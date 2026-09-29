import SwiftUI

/// The window shown from the menu bar. The system renders it on Liquid Glass; everything inside is
/// content, so it uses plain fills and hover highlights rather than more glass.
struct MenuBarPanel: View {
    @Environment(Monitor.self) private var monitor
    @Environment(AppSettings.self) private var settings
    @Environment(Account.self) private var account

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded: Set<String>
    @State private var listHeight: CGFloat = 0

    init(initiallyExpanded: Set<String> = []) {
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader()
            content
                // Skeleton → list and empty states crossfade instead of popping.
                .animation(Motion.crossfade, value: contentPhase)
            Divider()
                .padding(.horizontal, Metrics.edgeInset)
            PanelFooter()
        }
        .frame(width: Metrics.panelWidth)
        .containerShape(.rect(cornerRadius: Metrics.panelCornerRadius))
        // The panel's window is reused between openings, so refresh whenever it becomes key.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            monitor.refreshIfStale()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch monitor.summary {
        case .signedOut:
            ConnectGitHubView()
        case .needsRepositories:
            EmptyStateView(
                symbol: "book.closed",
                title: "Choose Repositories",
                message: "Pick the repositories whose pull requests you want PR Monitor to watch.",
                action: ("Choose Repositories…", .repositories)
            )
        case let .unavailable(error) where monitor.visibleSections.isEmpty:
            EmptyStateView(symbol: symbol(for: error), title: title(for: error), message: error.localizedDescription)
        default:
            if monitor.visibleSections.isEmpty {
                if monitor.lastUpdated == nil {
                    PullRequestListSkeleton()
                        .transition(.opacity)
                } else {
                    EmptyStateView(
                        symbol: "checkmark.circle",
                        title: "No Open Pull Requests",
                        message: settings.scope == .authored
                            ? "You don't have any open pull requests in the repositories you monitor."
                            : "There are no open pull requests in the repositories you monitor."
                    )
                }
            } else {
                list
                    .transition(.opacity)
            }
        }
    }

    /// Identifies which kind of content is showing, so switching between them crossfades.
    private var contentPhase: Int {
        switch monitor.summary {
        case .signedOut: 0
        case .needsRepositories: 1
        default: monitor.lastUpdated == nil ? 2 : (monitor.visibleSections.isEmpty ? 3 : 4)
        }
    }

    private var list: some View {
        ScrollView {
            // A plain VStack (not lazy) so the measured height is exact on the first frame; the
            // list is at most a few dozen rows.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(monitor.visibleSections) { section in
                    Section {
                        ForEach(section.reports) { report in
                            PullRequestRow(report: report, isExpanded: expansionBinding(for: report.id))
                        }
                    } header: {
                        SectionHeader(section: section)
                    }
                }
            }
            .padding(.bottom, Metrics.highlightInset)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { listHeight = $0 }
            .animation(reduceMotion ? nil : Motion.content, value: monitor.visibleReports.map(\.id))
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollEdgeEffectStyle(.soft, for: .top)
        // Grow with the content up to most of the screen, then scroll.
        .frame(height: min(max(listHeight, 1), maximumListHeight))
    }

    private var maximumListHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 900
        return min(screen - 180, 620)
    }

    private func expansionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isExpanded in
                if isExpanded { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }

    private func symbol(for error: GitHubError) -> String {
        switch error {
        case .offline: "wifi.slash"
        case .rateLimited: "hourglass"
        default: "exclamationmark.triangle"
        }
    }

    private func title(for error: GitHubError) -> String {
        switch error {
        case .offline: "You're Offline"
        case .rateLimited: "Taking a Short Break"
        default: "Couldn't Reach GitHub"
        }
    }
}

// MARK: - Header

private struct PanelHeader: View {
    @Environment(Monitor.self) private var monitor
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Pull Requests")
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(Motion.content, value: subtitle)
            }
            Spacer(minLength: 0)
            if monitor.summary.showsContent {
                Menu {
                    Picker("Show", selection: $settings.scope) {
                        Label("All Pull Requests", systemImage: "tray.full").tag(AppSettings.Scope.all)
                        Label("My Pull Requests", systemImage: "person").tag(AppSettings.Scope.authored)
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Toggle("Hide Drafts", isOn: $settings.hidesDrafts)
                } label: {
                    Label("Filter", systemImage: isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(isFiltered ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .contentTransition(.symbolEffect(.replace))
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.icon)
                .help("Filter pull requests")
            }
        }
        .padding(.leading, Metrics.edgeInset)
        .padding(.trailing, 6)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var isFiltered: Bool {
        settings.scope == .authored || settings.hidesDrafts
    }

    private var subtitle: String {
        let reports = monitor.visibleReports
        switch monitor.summary {
        case .signedOut: return "Not connected"
        case .needsRepositories: return "No repositories selected"
        case .unavailable where reports.isEmpty: return "Unavailable"
        default: break
        }
        guard monitor.lastUpdated != nil else { return "Loading…" }
        if reports.isEmpty { return "Nothing open" }

        let attention = reports.count { $0.status.needsAttention }
        let running = reports.count { $0.status == .running }
        var parts: [String] = []
        if attention > 0 { parts.append("\(attention) need\(attention == 1 ? "s" : "") attention") }
        if running > 0 { parts.append("\(running) in progress") }
        if parts.isEmpty { parts.append(reports.count == 1 ? "1 open, all clear" : "\(reports.count) open, all clear") }
        if settings.scope == .authored { parts.insert("Yours", at: 0) }
        return parts.joined(separator: " · ")
    }
}

private struct SectionHeader: View {
    let section: Monitor.Section

    var body: some View {
        HStack(spacing: 6) {
            Text("\(Text(section.repository.owner + "/").foregroundStyle(.tertiary))\(section.repository.name)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if let error = section.error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(error.localizedDescription)
                    .accessibilityLabel("Couldn't refresh: \(error.localizedDescription)")
            }
        }
        .padding(.horizontal, Metrics.edgeInset)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Footer

private struct PanelFooter: View {
    @Environment(Monitor.self) private var monitor
    @Environment(AppRouter.self) private var router
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 2) {
            status
                .padding(.leading, Metrics.edgeInset - 4)
            Spacer(minLength: 8)

            Button("Refresh", systemImage: "arrow.clockwise") { monitor.refresh() }
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: monitor.isRefreshing)
                .keyboardShortcut("r")
                .help("Refresh (⌘R)")
                .disabled(!monitor.summary.canRefresh)

            Button("Settings", systemImage: "gearshape") { router.showSettings(using: openSettings) }
                .keyboardShortcut(",")
                .help("Settings… (⌘,)")

            Menu {
                Button("Open GitHub") { NSWorkspace.shared.open(URL(string: "https://github.com/pulls")!) }
                Divider()
                Button("About PR Monitor") {
                    NSApp.activate()
                    NSApp.orderFrontStandardAboutPanel()
                }
                Button("Quit PR Monitor") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .menuIndicator(.hidden)
            .help("More")
        }
        .buttonStyle(.icon)
        .menuStyle(.button)
        .labelStyle(.iconOnly)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var status: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            Group {
                if let error = monitor.lastError, monitor.summary.showsContent {
                    Label(error.shortDescription, systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.orange)
                        .help(error.localizedDescription)
                } else if let updated = monitor.lastUpdated {
                    Text("Updated \(updated, format: .relative(presentation: .named, unitsStyle: .wide))")
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
            .font(.subheadline)
            .lineLimit(1)
        }
    }
}

extension Monitor.Summary {
    var showsContent: Bool {
        switch self {
        case .signedOut, .needsRepositories: false
        default: true
        }
    }

    var canRefresh: Bool { showsContent }
}

extension GitHubError {
    /// A few words for the footer; the full explanation is in the tooltip.
    var shortDescription: String {
        switch self {
        case .offline: "Offline"
        case .rateLimited: "Rate limited"
        case .unauthorized: "Signed out"
        case .server: "GitHub unavailable"
        default: "Couldn't refresh"
        }
    }
}
