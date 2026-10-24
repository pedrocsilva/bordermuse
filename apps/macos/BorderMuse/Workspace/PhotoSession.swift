import AppKit
import Observation
import BorderMuseGeometry
import BorderMuseImaging

@MainActor @Observable
final class PhotoSession {
    static let shared = PhotoSession()
    var photos: [Photo] = []
    var selectedID: UUID? {
        didSet { if oldValue != selectedID { loadPreview() } }
    }
    var settings = BorderSettings()
    var presets: [Preset]
    var selectedPreset: UUID?
    var settingsRevision = 0
    private(set) var invalidInputs: Set<NumericSetting> = []
    var preview: PreviewImage?
    var previewError: String?
    var isImporting = false
    var isExporting = false
    var completed = 0
    var total = 0
    var result: ExportResult?
    var issues: [PhotoIssue] = []
    var showIssues = false
    let loader = PhotoLoader()
    private let worker = ExportWorker()
    private let store: PresetStore
    private var importTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var pending: [URL] = []
    private var pendingIndex = 0
    private var knownFiles: Set<URL> = []
    init(store: PresetStore = PresetStore()) { self.store = store; presets = store.load() }
    var selected: Photo? {
        guard let id = selectedID else { return photos.first }
        return photos.first { $0.id == id } ?? photos.first
    }
    var layout: CanvasLayout? {
        guard let photo = selected, let options = try? settings.options else { return nil }
        return try? ImageProcessor.layout(for: photo.info, options: options)
    }
    var canExport: Bool { !photos.isEmpty && !isImporting && !isExporting && invalidInputs.isEmpty && (try? settings.options) != nil && layout != nil }
    var validationMessage: String? {
        if let field = NumericSetting.allCases.first(where: invalidInputs.contains) { return field.errorMessage }
        do {
            let options = try settings.options
            if let photo = selected { _ = try ImageProcessor.layout(for: photo.info, options: options) }
            return nil
        } catch { return ExportWorker.message(error) }
    }
    var exportTitle: String {
        if photos.isEmpty { return Strings.text("exportMenu") }
        return photos.count == 1 ? Strings.text("exportOne") : Strings.format("export", photos.count)
    }
    var settingsScope: String {
        if photos.isEmpty { return Strings.text("batchEmpty") }
        return photos.count == 1 ? Strings.text("batchOne") : Strings.format("batchAll", photos.count)
    }
    var exportSizeSummary: String {
        guard !invalidInputs.contains(.longEdge) else { return Strings.text("invalidSize") }
        return settings.reduceSize ? Strings.format("sizeLimit", settings.longEdge) : Strings.text("originalResolution")
    }

    func addPhotos() {
        guard !isExporting else { return }
        let panel = NSOpenPanel()
        panel.title = Strings.text("addPhotos")
        panel.allowedContentTypes = [.jpeg, .png, .tiff]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { importPhotos(panel.urls) }
    }
    func importPhotos(_ urls: [URL]) {
        pending.append(contentsOf: urls.filter(\.isFileURL))
        guard !isExporting else { return }
        guard !isImporting else { return }
        isImporting = true
        importTask = Task {
            while pendingIndex < pending.count && !Task.isCancelled {
                let url = pending[pendingIndex]; pendingIndex += 1
                let key = url.resolvingSymlinksInPath().standardizedFileURL
                do {
                    if knownFiles.contains(key), let index = photos.firstIndex(where: { $0.canonicalURL == key }) {
                        let refreshed = try await loader.load(url, id: photos[index].id)
                        try Task.checkCancellation()
                        if refreshed.info.version != photos[index].info.version {
                            photos[index] = refreshed
                            if selectedID == refreshed.id { loadPreview() }
                            result = nil
                        }
                        continue
                    }
                    let photo = try await loader.load(url)
                    try Task.checkCancellation()
                    photos.append(photo)
                    knownFiles.insert(photo.canonicalURL)
                    if selectedID == nil { selectedID = photo.id }
                } catch is CancellationError { break }
                catch { issues.append(PhotoIssue(url: url, message: ExportWorker.message(error, importing: true), canRetry: false)) }
            }
            pending = []; pendingIndex = 0
            isImporting = false
            importTask = nil
        }
    }
    func loadPreview() {
        previewTask?.cancel()
        preview = nil
        previewError = nil
        guard let photo = selected else { return }
        previewTask = Task {
            do {
                let image = try await loader.preview(photo.url, expectedVersion: photo.info.version)
                guard !Task.isCancelled else { return }
                preview = image
            } catch {
                guard !Task.isCancelled else { return }
                previewError = ExportWorker.message(error, importing: true)
            }
        }
    }
    func remove(_ photo: Photo) {
        guard !isExporting && !isImporting else { return }
        photos.removeAll { $0.id == photo.id }
        knownFiles.remove(photo.canonicalURL)
        if selectedID == photo.id { selectedID = photos.first?.id }
    }
    func clear() {
        guard !isExporting && !isImporting else { return }
        previewTask?.cancel(); preview = nil; previewError = nil; photos = []; selectedID = nil; result = nil; issues = []
        knownFiles = []
    }
    func chooseExportFolder(retry: Bool = false) {
        guard canExport else { return }
        let panel = NSOpenPanel()
        panel.title = Strings.text("chooseFolder"); panel.prompt = Strings.text("choose")
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            let failed = Set(issues.filter(\.canRetry).map(\.url))
            export(retry ? photos.filter { failed.contains($0.url) } : photos, to: url, refresh: retry)
        }
    }
    func export(_ snapshot: [Photo], to folder: URL, refresh: Bool = false) {
        guard !isExporting, !isImporting, invalidInputs.isEmpty, !snapshot.isEmpty, let options = try? settings.options else { return }
        isExporting = true; total = snapshot.count; completed = 0; result = nil
        issues.removeAll { $0.canRetry }
        exportTask = Task {
            var inputs = snapshot
            if refresh {
                for index in inputs.indices {
                    if Task.isCancelled { break }
                    // Retry explicitly acknowledges restored or updated source files.
                    // Keep unreadable inputs in the batch so the worker reports them.
                    if let photo = try? await loader.load(inputs[index].url, id: inputs[index].id) {
                        inputs[index] = photo
                        if let existing = photos.firstIndex(where: { $0.id == photo.id }) { photos[existing] = photo }
                    }
                }
                loadPreview()
            }
            let report = await worker.run(photos: inputs, folder: folder, options: options) { [weak self] progress in
                self?.completed = progress
            }
            result = report; issues.append(contentsOf: report.issues)
            isExporting = false; exportTask = nil
            if !pending.isEmpty { importPhotos([]) }
        }
    }
    func cancelExport() { exportTask?.cancel() }
    func cancelExportAndWait() async {
        let task = exportTask
        task?.cancel()
        await task?.value
    }
    func revealExports() {
        guard let outputs = result?.outputs, !outputs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(outputs)
    }
    func usePreset(_ id: UUID?) {
        selectedPreset = id
        if let preset = presets.first(where: { $0.id == id }) {
            settings = preset.settings; invalidInputs = []; settingsRevision &+= 1
        }
    }
    func setInputValidity(_ field: NumericSetting, valid: Bool) {
        if valid && invalidInputs.contains(field) { invalidInputs.remove(field) }
        else if !valid && !invalidInputs.contains(field) { invalidInputs.insert(field) }
    }
    func selectNeighbor(_ delta: Int) {
        guard !photos.isEmpty else { return }
        let index = photos.firstIndex(where: { $0.id == selectedID }) ?? 0
        selectedID = photos[min(photos.count - 1, max(0, index + delta))].id
    }
    func savePreset(name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, invalidInputs.isEmpty, (try? settings.options) != nil else { return }
        let preset = Preset(id: UUID(), name: clean, settings: settings)
        persistPresets(presets + [preset], selected: preset.id)
    }
    func deletePreset() { persistPresets(presets.filter { $0.id != selectedPreset }, selected: nil) }
    private func persistPresets(_ updated: [Preset], selected: UUID?) {
        do { try store.save(updated); presets = updated; selectedPreset = selected }
        catch { issues.append(PhotoIssue(url: store.url, message: Strings.text("presetError"), canRetry: false)); showIssues = true }
    }
    func settingsChanged() {
        if presets.first(where: { $0.id == selectedPreset })?.settings != settings { selectedPreset = nil }
        result = nil
    }
}
