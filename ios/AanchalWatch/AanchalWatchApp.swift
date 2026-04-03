// Aanchal Watch App — Entry Point
//
// watchOS 10+ SwiftUI app with a single SOS button.
// Supports both tap and the double-tap finger gesture (.primaryAction).

import SwiftUI

@main
struct AanchalWatchApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
