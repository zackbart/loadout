import SwiftUI
import HerdrKit

/// Screen 2: the tabs and panes/agents inside a single workspace, each with its
/// live status. Reads from the shared `SessionModel`, so status updates animate
/// in place.
struct WorkspaceDetailView: View {
    @Environment(SessionModel.self) private var session
    let workspaceID: WorkspaceID

    private var workspace: Workspace? { session.workspace(workspaceID) }

    var body: some View {
        Group {
            if let workspace {
                List {
                    ForEach(workspace.tabs) { tab in
                        Section {
                            ForEach(tab.panes) { pane in
                                NavigationLink(value: pane.id) {
                                    PaneRow(pane: pane)
                                }
                            }
                        } header: {
                            SectionEyebrow(tab.label)
                        }
                    }
                }
                .navigationTitle(workspace.label)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Workspace closed", systemImage: "xmark.rectangle",
                                       description: Text("This workspace is no longer available."))
            }
        }
    }
}

private struct PaneRow: View {
    let pane: Pane

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: pane.isAgent ? "cpu" : "terminal")
                .font(.callout)
                .foregroundStyle(pane.isAgent ? Theme.ink : Color.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(pane.title).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 8) {
                    Text(pane.id.rawValue)
                        .font(Theme.mono(11))
                        .foregroundStyle(.tertiary)
                    if let agent = pane.agent {
                        Text(agent)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 8)
            if pane.isAgent {
                StatusTag(status: pane.status)
            }
        }
        .padding(.vertical, 4)
    }
}
