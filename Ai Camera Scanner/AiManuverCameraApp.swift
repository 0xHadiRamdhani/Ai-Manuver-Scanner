import SwiftUI
import SwiftData

@main struct AiManuverCameraApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }.modelContainer(for: ScanItem.self)
    }
}
