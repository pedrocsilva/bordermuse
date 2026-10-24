import AppKit
import SwiftUI

// SDK 27 also exports a State macro. This alias selects the stable property
// wrapper, supported by macOS 14 and by Command Line Tools without SwiftUIMacros.
typealias ViewState<Value> = SwiftUI.State<Value>

@main
struct BorderMuseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ViewState private var session = PhotoSession.shared
    var body: some Scene {
        Window(Strings.text("appName"), id: "main") {
            WorkspaceView(session: session)
                .environment(\.locale, Locale(identifier: "en_US"))
        }
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(Strings.text("addPhotos")) { session.addPhotos() }
                    .keyboardShortcut("o").disabled(session.isExporting)
                Button(Strings.text("exportMenu")) { session.chooseExportFolder() }
                    .keyboardShortcut("e", modifiers: [.command, .shift]).disabled(!session.canExport)
                Divider()
                Button(Strings.text("clear")) { session.clear() }
                    .disabled(session.isExporting || session.isImporting || session.photos.isEmpty)
            }
            CommandGroup(replacing: .appInfo) {
                Button(Strings.text("about")) { NSApp.orderFrontStandardAboutPanel(nil) }
            }
            CommandGroup(replacing: .appVisibility) {
                Button(Strings.text("hide")) { NSApp.hide(nil) }.keyboardShortcut("h")
                Button(Strings.text("hideOthers")) { NSApp.hideOtherApplications(nil) }
                    .keyboardShortcut("h", modifiers: [.command, .option])
                Button(Strings.text("showAll")) { NSApp.unhideAllApplications(nil) }
            }
            CommandGroup(replacing: .appTermination) {
                Button(Strings.text("quit")) { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
        }
    }
}

/// Finder opening and graceful cancellation when the app quits.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func application(_ application: NSApplication, open urls: [URL]) { PhotoSession.shared.importPhotos(urls) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard PhotoSession.shared.isExporting else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = Strings.text("closeTitle"); alert.informativeText = Strings.text("closeMessage")
        alert.addButton(withTitle: Strings.text("keepWorking")); alert.addButton(withTitle: Strings.text("stopQuit"))
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        // Let the worker clean up its temporary file before exiting.
        Task {
            await PhotoSession.shared.cancelExportAndWait()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
