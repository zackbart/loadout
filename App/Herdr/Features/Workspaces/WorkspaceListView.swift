import SwiftUI
import HerdrKit

/// Screen 1: the list of workspaces with live aggregate agent status. Hosts the
/// `NavigationStack` and registers destinations for the drill-down screens.
struct WorkspaceListView: View {
    @Environment(SessionModel.self) private var session
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            List {
                if let error = session.loadError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(Theme.blocked)
                }
                ForEach(session.workspaces) { workspace in
                    NavigationLink(value: workspace.id) {
                        WorkspaceRow(workspace: workspace)
                    }
                }
            }
            .navigationDestination(for: WorkspaceID.self) { id in
                WorkspaceDetailView(workspaceID: id)
            }
            .navigationDestination(for: PaneID.self) { id in
                PaneView(paneID: id)
            }
            .refreshable { await session.refresh() }
            .overlay {
                if session.workspaces.isEmpty && session.loadError == nil {
                    ContentUnavailableView("No workspaces", systemImage: "rectangle.3.group",
                                           description: Text("Create one with `herdr workspace create`."))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { Task { await app.disconnect() } } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                    .tint(Theme.ink)
                    .accessibilityLabel("Disconnect")
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Workspaces").font(.headline)
                        HStack(spacing: 5) {
                            StatusDot(status: .idle, size: 6)
                            Text(session.label)
                                .font(Theme.mono(10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .tint(Theme.prompt)
    }
}

private struct WorkspaceRow: View {
    let workspace: Workspace

    private var agentCount: Int { workspace.agentPanes.count }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(workspace.aggregateStatus.color)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(workspace.label)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(agentCount) agent\(agentCount == 1 ? "" : "s")")
                        .font(Theme.mono(11))
                        .foregroundStyle(.tertiary)
                }
                if let cwd = workspace.cwd {
                    Text(cwd)
                        .font(Theme.mono(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                StatusSummary(counts: workspace.agentCounts())
            }
        }
        .padding(.vertical, 6)
        .fixedSize(horizontal: false, vertical: true)
    }
}
