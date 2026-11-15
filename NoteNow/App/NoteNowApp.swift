import SwiftUI

@main
struct NoteNowApp: App {
    @StateObject private var store = NotebookStore()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
                .preferredColorScheme(.light)
        }
    }
}
