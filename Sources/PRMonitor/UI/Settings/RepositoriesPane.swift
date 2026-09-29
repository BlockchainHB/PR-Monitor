import SwiftUI

struct RepositoriesPane: View {
    @Environment(AppSettings.self) private var settings
    @State private var isPickerPresented = false

    var body: some View {
        @Bindable var settings = settings
        Group {
            if settings.repositories.isEmpty {
                ContentUnavailableView {
                    Label("No Repositories", systemImage: "book.closed")
                } description: {
                    Text("Choose the repositories whose pull requests you want to monitor.")
                } actions: {
                    Button("Add Repositories…") { isPickerPresented = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Form {
                    Section {
                        ForEach($settings.repositories) { $repository in
                            RepositoryRow(repository: $repository) { settings.untrack(repository.id) }
                        }
                    } header: {
                        HStack {
                            Text("Monitored Repositories")
                            Spacer()
                            AddButton(help: "Add repositories") { isPickerPresented = true }
                        }
                    } footer: {
                        Text("Turn a repository off to pause it without losing it.")
                    }
                }
                .formStyle(.grouped)
            }
        }
        .sheet(isPresented: $isPickerPresented) {
            RepositoryPicker()
        }
    }
}

private struct RepositoryRow: View {
    @Binding var repository: TrackedRepository
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(repository.id.name)
                Text(repository.id.owner)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .opacity(repository.isEnabled ? 1 : 0.5)
            Spacer()
            Toggle("Monitor \(repository.id.fullName)", isOn: $repository.isEnabled)
                .labelsHidden()
            Button(role: .destructive, action: remove) {
                Image(systemName: "minus.circle.fill")
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Stop monitoring \(repository.id.fullName)")
            .accessibilityLabel("Remove \(repository.id.fullName)")
        }
        .contextMenu {
            Button("Open on GitHub") { NSWorkspace.shared.open(repository.id.url) }
            Button("Remove", role: .destructive, action: remove)
        }
    }
}

/// Search the repositories you can access, or paste any `owner/name` or GitHub URL.
private struct RepositoryPicker: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Account.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var repositories: [RemoteRepository] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Add Repositories")
                    .font(.headline)
                TextField("Search, or paste owner/name or a GitHub URL", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
                    .onSubmit(addTypedRepository)
            }
            .padding(16)

            Divider()

            List {
                if let typed = typedRepository {
                    Button {
                        addTypedRepository()
                    } label: {
                        Label("Add \(typed.fullName)", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
                ForEach(filtered) { repository in
                    RemoteRepositoryRow(repository: repository, isTracked: settings.isTracking(repository.id)) {
                        if settings.isTracking(repository.id) {
                            settings.untrack(repository.id)
                        } else {
                            settings.track(repository.id)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .overlay { overlay }
            .animation(Motion.crossfade, value: repositories.isEmpty)

            Divider()

            HStack {
                Text("\(settings.repositories.count) monitored")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 460, height: 520)
        .task { await load() }
        .onAppear { isSearchFocused = true }
    }

    @ViewBuilder
    private var overlay: some View {
        if isLoading && repositories.isEmpty {
            ListRowSkeleton(count: 7)
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
        } else if let loadError, repositories.isEmpty {
            ContentUnavailableView("Couldn't Load Repositories", systemImage: "exclamationmark.triangle", description: Text(loadError))
        } else if !isLoading, filtered.isEmpty, typedRepository == nil {
            ContentUnavailableView.search(text: query)
        }
    }

    private var filtered: [RemoteRepository] {
        let text = query.trimmed
        guard !text.isEmpty else { return repositories }
        return repositories.filter { $0.id.fullName.localizedStandardContains(text) }
    }

    /// A parsable repository that isn't in the list (e.g. from an org the token can see but doesn't belong to).
    private var typedRepository: RepositoryID? {
        guard let id = RepositoryID(parsing: query), !settings.isTracking(id) else { return nil }
        return repositories.contains { $0.id == id } ? nil : id
    }

    private func addTypedRepository() {
        guard let id = RepositoryID(parsing: query) else { return }
        settings.track(id)
        query = ""
    }

    private func load() async {
        guard let token = account.credential?.token else {
            loadError = "Sign in to see your repositories."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            repositories = try await GitHubClient(token: token).viewerRepositories()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct RemoteRepositoryRow: View {
    let repository: RemoteRepository
    let isTracked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: isTracked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isTracked ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(repository.id.fullName)
                            .foregroundStyle(.primary)
                        if repository.isPrivate {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Private")
                        }
                    }
                    if let description = repository.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isTracked ? .isSelected : [])
    }
}

/// The small "+" that sits at the trailing edge of a section header.
struct AddButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }
}
