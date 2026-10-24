import SwiftUI
import BorderMuseGeometry

struct CanvasPreview: View {
    let name: String
    let preview: PreviewImage?
    let failure: String?
    let layout: CanvasLayout
    var body: some View {
        GeometryReader { geometry in
            let scale = max(0, min((geometry.size.width - 72) / CGFloat(layout.width),
                                   (geometry.size.height - 72) / CGFloat(layout.height)))
            let width = CGFloat(layout.width) * scale
            let height = CGFloat(layout.height) * scale
            ZStack(alignment: .topLeading) {
                Color.white
                if let preview {
                    Image(decorative: preview.image, scale: 1)
                        .resizable()
                        .frame(width: CGFloat(layout.width - layout.left - layout.right) * scale,
                               height: CGFloat(layout.height - layout.top - layout.bottom) * scale)
                        .offset(x: CGFloat(layout.left) * scale, y: CGFloat(layout.top) * scale)
                } else if let failure {
                    Text(failure).font(.callout).foregroundStyle(.black.opacity(0.7))
                        .multilineTextAlignment(.center).padding(20).frame(width: width, height: height)
                } else {
                    ProgressView().frame(width: width, height: height)
                }
            }
            .frame(width: width, height: height)
            .compositingGroup()
            .shadow(color: .black.opacity(0.12), radius: 9, y: 3)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Strings.format("previewSummary", name,
                failure ?? (preview == nil ? Strings.text("loading") : Strings.format("output", layout.width, layout.height))))
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("exportPreview")
        }
    }
}

struct Filmstrip: View {
    @Bindable var session: PhotoSession
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool
    private var palette: WorkspacePalette { WorkspacePalette(colorScheme) }
    var body: some View {
        let selection = session.selectedID
        ScrollViewReader { proxy in
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                ForEach(session.photos) { photo in
                    Button {
                        session.selectedID = photo.id
                        isFocused = true
                    } label: {
                        PhotoThumbnail(photo: photo, loader: session.loader)
                            .background(palette.stage)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay {
                                RoundedRectangle(cornerRadius: 5).stroke(selection == photo.id ? palette.accent : .clear, lineWidth: 2)
                            }
                            .overlay(alignment: .bottomTrailing) {
                                if selection == photo.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(palette.onAccent, palette.accent)
                                        .font(.system(size: 13, weight: .semibold))
                                        .padding(4).accessibilityHidden(true)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .id(photo.id)
                    .help(photo.url.lastPathComponent)
                    .accessibilityLabel(Strings.format("selectPhoto", photo.url.lastPathComponent))
                    .accessibilityIdentifier("photo-\(photo.url.lastPathComponent)")
                    .accessibilityAddTraits(selection == photo.id ? .isSelected : [])
                    .contextMenu {
                        Button(Strings.text("remove"), role: .destructive) { session.remove(photo) }
                            .disabled(session.isExporting || session.isImporting)
                    }
                }
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(height: 104)
        .focusable(interactions: .edit).focused($isFocused)
        .accessibilityLabel(Strings.text("photos"))
        .accessibilityHint(Strings.text("photosKeyboardHelp"))
        .onKeyPress(.leftArrow) { session.selectNeighbor(-1); return .handled }
        .onKeyPress(.rightArrow) { session.selectNeighbor(1); return .handled }
        .onDeleteCommand { if let selected = session.selected { session.remove(selected) } }
        .onChange(of: session.selectedID) { if let id = session.selectedID { proxy.scrollTo(id, anchor: .center) } }
        }
    }
}

private struct PhotoThumbnail: View {
    let photo: Photo
    let loader: PhotoLoader
    @ViewState private var image: PreviewImage?
    var body: some View {
        Group {
            if let image { Image(decorative: image.image, scale: 1).resizable().scaledToFit() }
            else { Color.clear }
        }
        .frame(width: 78, height: 64).padding(6)
        .task(id: photo.info.version) {
            image = nil
            let loaded = try? await loader.thumbnail(photo.url)
            if !Task.isCancelled { image = loaded }
        }
        .onDisappear { image = nil }
    }
}
