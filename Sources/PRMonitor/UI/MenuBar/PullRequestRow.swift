import SwiftUI

/// One pull request, in two light lines: the title, then a colored status phrase with the PR's
/// details. Clicking opens it on GitHub, like choosing a menu item; the chevron reveals each agent.
struct PullRequestRow: View {
    let report: PullRequestReport
    @Binding var isExpanded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    private var pr: PullRequest { report.pullRequest }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Button { openURL(pr.url) } label: { summary }
                    .buttonStyle(RowButtonStyle())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityHint("Opens the pull request on GitHub")

                disclosureButton
            }

            if isExpanded {
                AgentList(report: report)
                    .transition(reduceMotion ? .opacity : .disclosure)
            }
        }
        .padding(.horizontal, Metrics.highlightInset)
        .contextMenu { contextMenu }
    }

    // MARK: - Summary

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            StatusGlyph(status: report.status, isDraft: pr.isDraft && report.status == .quiet)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }

            VStack(alignment: .leading, spacing: 2) {
                Text(pr.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                detailLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, Metrics.rowPadding)
        .padding(.trailing, 2)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "3 threads · #482 · hasaam · 3m". The glyph already says ready/failed/running, so the line
    /// only leads with what the glyph can't: which agent failed, how many threads, how far along.
    private var detailLine: some View {
        var details = ["#\(pr.number)"]
        if let author = pr.author { details.append(author) }
        details.append(pr.updatedAt.compactAge())
        if pr.isDraft { details.append("Draft") }

        return HStack(spacing: 0) {
            if let statusDetail {
                Text(statusDetail + " · ").foregroundStyle(report.status.tint)
            }
            Text(details.joined(separator: " · "))
                .foregroundStyle(.secondary)
            if pr.mergeable == .conflicting {
                Text(" · Conflicts").foregroundStyle(.red)
            }
        }
        .font(.subheadline)
        .lineLimit(1)
    }

    /// The part of the status the glyph can't express, or nil when the glyph says it all.
    private var statusDetail: String? {
        switch report.status {
        case .failing:
            let failed = report.agents.filter { $0.state == .failed }.map(\.name)
            guard let first = failed.first else { return nil }
            return failed.count == 1 ? first : "\(first) +\(failed.count - 1)"
        case .needsReview:
            let threads = report.openThreadCount
            if threads > 0 { return threads == 1 ? "1 thread" : "\(threads) threads" }
            return "Changes requested"
        case .running:
            return "\(report.finishedAgentCount) of \(report.agents.count)"
        case .ready:
            return pr.reviewDecision == .approved ? "Approved" : nil
        case .quiet:
            return nil
        }
    }

    /// Full wording for VoiceOver, which can't see the glyph.
    private var spokenStatus: String {
        switch report.status {
        case .failing: statusDetail.map { "\($0) failed" } ?? "Failing"
        case .needsReview: statusDetail.map { "\($0) to review" } ?? "Needs review"
        case .running: "Running, \(statusDetail ?? "")"
        case .ready: pr.reviewDecision == .approved ? "Ready, approved" : "Ready"
        case .quiet: "No checks yet"
        }
    }

    // MARK: - Disclosure

    private var disclosureButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : Motion.disclosure) { isExpanded.toggle() }
        } label: {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .buttonStyle(.icon)
        .disabled(report.agents.isEmpty)
        .opacity(report.agents.isEmpty ? 0 : 1)
        .help(isExpanded ? "Hide agents" : "Show agents")
        .accessibilityLabel(isExpanded ? "Hide agents" : "Show agents")
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenu: some View {
        Button("Open Pull Request", systemImage: "arrow.up.right.square") { openURL(pr.url) }
        Button("Open Checks", systemImage: "checklist") { openURL(pr.checksURL) }
        Divider()
        Button("Copy Link", systemImage: "link") { copy(pr.url.absoluteString) }
        Button("Copy Title", systemImage: "doc.on.doc") { copy("#\(pr.number) \(pr.title)") }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private var accessibilityLabel: String {
        var parts = ["\(pr.title), pull request \(pr.number)", spokenStatus]
        if pr.isDraft { parts.append("Draft") }
        if pr.mergeable == .conflicting { parts.append("Has conflicts") }
        parts += report.agents.map { "\($0.name): \($0.summary)" }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Agent list

/// The expanded per-agent breakdown: quiet, compact rows that link to each check or review.
private struct AgentList: View {
    let report: PullRequestReport
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(report.agents) { agent in
                Button {
                    openURL(agent.url ?? report.pullRequest.url)
                } label: {
                    HStack(spacing: 7) {
                        AgentGlyph(state: agent.state)
                        Text(agent.name)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(detail(for: agent))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .font(.subheadline)
                    .padding(.vertical, 3)
                    // Align with the title column: glyph (20) + spacing (10).
                    .padding(.leading, Metrics.rowPadding + 30)
                    .padding(.trailing, Metrics.rowPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(RowButtonStyle())
                .help(agent.url == nil ? "Open pull request" : "Open details")
                .accessibilityLabel("\(agent.name), \(agent.summary)")
            }
        }
        .padding(.bottom, 6)
    }

    private func detail(for agent: AgentReport) -> String {
        guard let finished = agent.finishedAt, agent.state != .running else { return agent.summary }
        return "\(agent.summary) · \(finished.compactAge())"
    }
}
