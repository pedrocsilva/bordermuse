import SwiftUI

struct Inspector: View {
    @Bindable var session: PhotoSession
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @ViewState private var showSave = false
    @ViewState private var presetName = ""
    @ViewState private var expanded = false
    @ViewState private var photoSize: PhotoSize = .original
    private enum PhotoSize: Hashable { case original, small, custom }
    private let ratios = ["original", "1:1", "5:4", "4:5", "3:2", "2:3", "16:9", "9:16", "2:1", "1:2"]
    private var palette: WorkspacePalette { WorkspacePalette(colorScheme) }
    private var exportForeground: Color {
        guard session.canExport else { return palette.secondary }
        return controlActiveState == .inactive ? palette.primary : palette.onAccent
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(Strings.text("borderSettings")).font(WorkspaceStyle.section)
                        Text(session.settingsScope).font(WorkspaceStyle.detail).foregroundStyle(palette.secondary)
                            .accessibilityIdentifier("settingsScope")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(Strings.text("preset")).foregroundStyle(palette.secondary)
                            Spacer()
                            Button(Strings.text("savePresetShort")) { presetName = ""; showSave = true }
                                .controlSize(.small).disabled(session.validationMessage != nil)
                                .accessibilityLabel(Strings.text("savePreset"))
                                .accessibilityIdentifier("savePreset")
                        }
                        HStack(spacing: 5) {
                            Picker(Strings.text("preset"), selection: Binding(get: { session.selectedPreset }, set: { session.usePreset($0) })) {
                                Text(Strings.text("custom")).tag(nil as UUID?)
                                Text(Strings.text("mobileReferencePreset")).tag(Optional(Preset.mobileReferenceID))
                                ForEach(session.presets) { Text($0.name).tag(Optional($0.id)) }
                            }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("presetPicker")
                                .help(Strings.text("mobileReferenceHelp"))
                                .accessibilityHint(Strings.text("mobileReferenceHelp"))
                            if session.canDeleteSelectedPreset {
                                Menu {
                                    Button(Strings.text("deletePreset"), role: .destructive) { session.deletePreset() }
                                } label: { Image(systemName: "ellipsis") }
                                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24, height: 24)
                                .accessibilityLabel(Strings.text("presetActions")).help(Strings.text("presetActions")).accessibilityIdentifier("presetActions")
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Strings.text("ratio")).foregroundStyle(palette.secondary)
                        Picker(Strings.text("ratio"), selection: $session.settings.ratio) {
                            ForEach(ratios, id: \.self) { Text($0 == "original" ? Strings.text("original") : $0).tag($0) }
                        }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("ratioPicker")
                    }
                    VStack(spacing: 10) {
                        HStack {
                            Text(Strings.text("thickness")).foregroundStyle(palette.secondary)
                            Spacer()
                            numberField(.thickness, value: $session.settings.thickness).frame(width: 52)
                        }
                        Slider(value: Binding(get: { Double(session.settings.thickness) }, set: { session.settings.thickness = Int($0.rounded()) }), in: 0...50)
                            .accessibilityLabel(Strings.text("thickness"))
                            .accessibilityValue(String(session.settings.thickness))
                            .accessibilityAdjustableAction { direction in
                                switch direction {
                                case .increment: session.settings.thickness = min(50, session.settings.thickness + 1)
                                case .decrement: session.settings.thickness = max(0, session.settings.thickness - 1)
                                @unknown default: break
                                }
                            }
                            .accessibilityIdentifier("thicknessSlider")
                    }
                    Divider()
                    if let message = session.validationMessage {
                        Label(message, systemImage: "exclamationmark.circle").font(WorkspaceStyle.detail).foregroundStyle(palette.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .ignore).accessibilityLabel(message)
                            .accessibilityIdentifier("settingsError")
                    }
                    DisclosureGroup(Strings.text("exportOptions"), isExpanded: $expanded) {
                        VStack(alignment: .leading, spacing: 16) {
                            Picker(Strings.text("photoSize"), selection: $photoSize) {
                                Text(Strings.text("original")).tag(PhotoSize.original)
                                Text(Strings.text("size2048")).tag(PhotoSize.small)
                                Text(Strings.text("custom")).tag(PhotoSize.custom)
                            }
                            .accessibilityIdentifier("photoSizePicker")
                            .accessibilityHint(Strings.text("sizeHelp"))
                            .help(Strings.text("sizeHelp"))
                            if photoSize == .custom {
                                HStack {
                                    Text(Strings.text("longEdge"))
                                    Spacer()
                                    numberField(.longEdge, value: $session.settings.longEdge).frame(width: 78)
                                }
                            }
                            if session.settings.reduceSize {
                                Text(Strings.text("sizeBeforeBorder")).font(WorkspaceStyle.detail).foregroundStyle(palette.secondary)
                                    .help(Strings.text("sizeHelp"))
                            }
                            HStack {
                                Text(Strings.text("quality"))
                                Spacer()
                                numberField(.quality, value: $session.settings.quality).frame(width: 52)
                            }
                            Toggle(Strings.text("metadata"), isOn: $session.settings.keepMetadata)
                            Text(Strings.text("metadataHelp")).font(WorkspaceStyle.detail).foregroundStyle(palette.secondary)
                            Text(Strings.text("formatHelp")).font(WorkspaceStyle.detail).foregroundStyle(palette.secondary)
                        }.padding(.top, 14)
                    }
                }.padding(22)
            }.disabled(session.isExporting)
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                VStack(spacing: 7) {
                    summaryRow("summarySize", value: session.exportSizeSummary, identifier: "exportSizeSummary")
                    summaryRow("summaryFormat", value: Strings.text("sourceFormat"), identifier: "exportFormatSummary")
                    summaryRow("summaryMetadata", value: Strings.text(session.settings.keepMetadata ? "metadataKept" : "metadataRemoved"), identifier: "exportMetadataSummary")
                        .help(Strings.text("metadataHelp"))
                }.font(WorkspaceStyle.detail)
                Divider().overlay(palette.divider)
                if session.isExporting {
                    ProgressView(value: Double(max(0, session.completed - 1)), total: Double(max(1, session.total)))
                    HStack {
                        Text(Strings.format("exporting", session.completed, session.total)).font(WorkspaceStyle.detail).foregroundStyle(palette.secondary)
                        Spacer()
                        Button(Strings.text("cancel")) { session.cancelExport() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("cancelExport")
                    }
                } else {
                    Button { session.chooseExportFolder() } label: {
                        Text(session.exportTitle).foregroundStyle(exportForeground)
                            .frame(maxWidth: .infinity)
                    }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(!session.canExport)
                        .accessibilityIdentifier("exportButton")
                }
            }.padding(22)
        }
        .frame(width: WorkspaceStyle.inspectorWidth)
        .background(palette.panel)
        .onChange(of: session.settings) { session.settingsChanged() }
        .onChange(of: session.settings.reduceSize) { if session.settings.reduceSize { expanded = true } }
        .onAppear { synchronizePhotoSize(); if session.settings.reduceSize { expanded = true } }
        .onChange(of: session.settingsRevision) { synchronizePhotoSize() }
        .onChange(of: photoSize) {
            session.settings.reduceSize = photoSize != .original
            if photoSize == .small { session.settings.longEdge = 2048 }
            if photoSize != .custom { session.setInputValidity(.longEdge, valid: true) }
        }
        .sheet(isPresented: $showSave) {
            VStack(alignment: .leading, spacing: 20) {
                Text(Strings.text("savePreset")).font(.headline)
                TextField(Strings.text("presetName"), text: $presetName).onSubmit { save() }.accessibilityIdentifier("presetName")
                HStack {
                    Spacer()
                    Button(Strings.text("cancel"), role: .cancel) { showSave = false }
                    Button(Strings.text("save")) { save() }.keyboardShortcut(.defaultAction)
                        .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 320)
        }
    }
    private func synchronizePhotoSize() {
        photoSize = !session.settings.reduceSize ? .original : session.settings.longEdge == 2048 ? .small : .custom
    }
    private func summaryRow(_ key: String, value: String, identifier: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(Strings.text(key)).foregroundStyle(palette.secondary)
            Spacer(minLength: 0)
            Text(value).lineLimit(1).help(value).accessibilityIdentifier(identifier)
        }
    }
    private func numberField(_ field: NumericSetting, value: Binding<Int>) -> some View {
        IntegerSettingField(field: field, value: value, revision: session.settingsRevision) { valid in
            session.setInputValidity(field, valid: valid)
        }
    }
    private func save() {
        guard !presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        session.savePreset(name: presetName); showSave = false
    }
}

/// A deliberate edit buffer: invalid text remains visible and blocks export.
/// Parent updates (slider/preset) resynchronize it, even while the field has focus.
private struct IntegerSettingField: View {
    let field: NumericSetting
    @Binding var value: Int
    let revision: Int
    let validity: (Bool) -> Void
    @ViewState private var draft: String
    init(field: NumericSetting, value: Binding<Int>, revision: Int, validity: @escaping (Bool) -> Void) {
        self.field = field; _value = value; self.revision = revision; self.validity = validity
        _draft = ViewState(wrappedValue: String(value.wrappedValue))
    }
    var body: some View {
        TextField(Strings.text(field.rawValue), text: $draft)
            .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
            .accessibilityIdentifier(field.rawValue + "Field")
            .accessibilityHint(field.errorMessage)
            .onChange(of: draft) { validate() }
            .onChange(of: value) { if field.parse(draft) != value { synchronize() } }
            .onChange(of: revision) { synchronize() }
            .onAppear { validate() }
            .onDisappear { validity(true) }
            .onSubmit { if let parsed = field.parse(draft) { draft = String(parsed) } }
    }
    private func validate() {
        guard let parsed = field.parse(draft) else { validity(false); return }
        if value != parsed { value = parsed }
        validity(true)
    }
    private func synchronize() { draft = String(value); validity(true) }
}
