import SwiftUI

struct WorkspaceView: View {
    @Bindable var session: PhotoSession
    @Environment(\.colorScheme) private var colorScheme
    @ViewState private var isTargeted = false
    @ViewState private var retryAfterIssues = false
    private var palette: WorkspacePalette { WorkspacePalette(colorScheme) }
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if let selected = session.selected {
                    HStack(spacing: 16) {
                        Text(selected.url.lastPathComponent).fontWeight(.medium)
                            .lineLimit(1).truncationMode(.middle).help(selected.url.lastPathComponent)
                            .accessibilityIdentifier("previewFilename")
                        Spacer(minLength: 0)
                        if let index = session.photos.firstIndex(where: { $0.id == selected.id }) {
                            Text(Strings.format("position", index + 1, session.photos.count))
                                .font(WorkspaceStyle.detail).foregroundStyle(palette.secondary)
                                .fixedSize().accessibilityIdentifier("photoPosition")
                        }
                    }.padding(.horizontal, 24).frame(height: 46).background(palette.panel)
                }
                ZStack {
                    palette.stage
                    if session.selected != nil, let layout = session.layout {
                        CanvasPreview(name: session.selected?.url.lastPathComponent ?? "", preview: session.preview, failure: session.previewError, layout: layout)
                    } else if session.photos.isEmpty {
                        emptyState
                    }
                }
                .overlay { if isTargeted { Rectangle().strokeBorder(Color.accentColor, lineWidth: 3) } }
                .dropDestination(for: URL.self) { urls, _ in
                    guard !session.isExporting else { return false }
                    session.importPhotos(urls); return true
                } isTargeted: { isTargeted = $0 }
                if !session.photos.isEmpty { Divider().overlay(palette.divider); Filmstrip(session: session).background(palette.panel) }
                Divider().overlay(palette.divider)
                status.padding(.horizontal, 20).frame(height: 42).background(palette.panel)
            }
            Divider().overlay(palette.divider)
            Inspector(session: session)
        }
        .frame(minWidth: 900, minHeight: 620)
        .font(WorkspaceStyle.body).foregroundStyle(palette.primary)
        .tint(palette.accent).background(palette.panel)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { session.addPhotos() } label: { Label(Strings.text("addPhotos"), systemImage: "plus") }
                    .disabled(session.isExporting)
                    .accessibilityIdentifier("addPhotosToolbar")
            }
        }
        .sheet(isPresented: $session.showIssues, onDismiss: {
            if retryAfterIssues { retryAfterIssues = false; session.chooseExportFolder(retry: true) }
        }) {
            IssueList(session: session) { retryAfterIssues = true; session.showIssues = false }
        }
    }
    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.on.rectangle").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(palette.secondary)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(Strings.text("emptyTitle")).font(.system(size: 23, weight: .medium))
                Text(Strings.text("emptySubtitle")).foregroundStyle(palette.secondary)
            }
            Button(Strings.text("addPhotos")) { session.addPhotos() }.controlSize(.large)
                .accessibilityIdentifier("addPhotosEmpty")
            Text(Strings.text("formats")).font(WorkspaceStyle.detail).foregroundStyle(palette.secondary)
        }.padding(32)
    }
    private var status: some View {
        HStack(spacing: 12) {
            if session.isImporting {
                ProgressView().controlSize(.small)
                Text(Strings.text("loading"))
            } else if let result = session.result {
                Text(Strings.format(result.canceled ? "cancelled" : "complete", result.outputs.count))
                    .accessibilityIdentifier("exportStatus")
                if !result.outputs.isEmpty { Button(Strings.text("showFinder")) { session.revealExports() }.buttonStyle(.link).accessibilityIdentifier("showFinder") }
            } else if let layout = session.layout {
                Text(Strings.format("contentSize", layout.width - layout.left - layout.right,
                                    layout.height - layout.top - layout.bottom)).monospacedDigit()
                    .accessibilityIdentifier("contentSize")
            }
            Spacer(minLength: 4)
            if !session.issues.isEmpty {
                Button(Strings.format("issues", session.issues.count)) { session.showIssues = true }.buttonStyle(.link).accessibilityIdentifier("reviewIssues")
            } else if let layout = session.layout {
                Text(Strings.format("canvasSize", layout.width, layout.height)).monospacedDigit()
                    .accessibilityIdentifier("outputSize")
            }
        }.font(WorkspaceStyle.detail).foregroundStyle(palette.secondary).lineLimit(1).accessibilityElement(children: .contain)
    }
}

private struct IssueList: View {
    @Bindable var session: PhotoSession
    let retry: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Strings.text("issuesTitle")).font(.headline)
            List(session.issues) { issue in
                VStack(alignment: .leading, spacing: 5) {
                    Text(issue.url.lastPathComponent).fontWeight(.medium)
                    Text(issue.message).foregroundStyle(.primary.opacity(0.72)).textSelection(.enabled)
                }.padding(.vertical, 6)
            }
            HStack {
                if session.issues.contains(where: \.canRetry) {
                    Button(Strings.text("retry"), action: retry).disabled(!session.canExport).accessibilityIdentifier("retryFailed")
                }
                Spacer()
                Button(Strings.text("done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 540, height: 360)
    }
}
