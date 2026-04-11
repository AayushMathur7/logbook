import LogbookCore
import SwiftUI

@main
struct LogbookApp: App {
    @StateObject private var model = AppModel()
    
    var body: some Scene {
        WindowGroup("Log Book") {
            ContentView(model: model)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 700, height: 500)
        .windowResizability(.contentSize)
    }
}
