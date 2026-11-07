import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            guard let model = AppModel.current else { return .terminateNow }
            return model.shouldQuit(confirm: Self.confirmQuitWithUnsavedText) ? .terminateNow : .terminateCancel
        }
    }

    @MainActor private static func confirmQuitWithUnsavedText() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Couldn't save your latest changes"
        alert.informativeText = "If you quit now, those changes will be lost."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Quit Anyway")
        return alert.runModal() == .alertSecondButtonReturn
    }
}

@main
struct ClaudetteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
        Snapshot.runIfRequested()
        _model = StateObject(wrappedValue: AppModel.live())
    }

    var body: some Scene {
        Window("Claudette", id: "main") {
            RootView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { model.newFile() }
                    .keyboardShortcut("n")
                Divider()
                Button("Connect Folder…") { model.chooseFolderToConnect() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Import…") { model.chooseFilesToImport() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .sidebar) {
                Button(model.isFileListOpen ? "Hide File List" : "Show File List") {
                    model.isFileListOpen.toggle()
                }
                .keyboardShortcut("\\")
                Button(model.viewMode == .formatted ? "Show Markdown" : "Show Formatted") {
                    model.viewMode = model.viewMode == .formatted ? .markdown : .formatted
                }
                .keyboardShortcut("e")
                Divider()
                Picker("Theme", selection: $model.themeID) {
                    ForEach(Theme.all, id: \.id) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
            }
        }
    }
}
