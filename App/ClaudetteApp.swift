import SwiftUI

@main
struct ClaudetteApp: App {
    init() {
        Snapshot.runIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            Text("Claudette")
        }
    }
}
