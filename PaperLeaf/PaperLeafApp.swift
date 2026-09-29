import SwiftUI

@main
struct PaperLeafApp: App {
    @StateObject private var store = NotebookStore()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
                .tint(Color(red: 0.22, green: 0.39, blue: 0.82))
        }
    }
}
