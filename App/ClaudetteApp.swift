import SwiftUI

@main
struct ClaudetteApp: App {
    @StateObject private var model: AppModel

    init() {
        Snapshot.runIfRequested()
        _model = StateObject(wrappedValue: AppModel.live())
    }

    var body: some Scene {
        WindowGroup {
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
