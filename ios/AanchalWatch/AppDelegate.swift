// Aanchal Watch App — App Delegate
//
// Activates the WCSession as soon as the watch app launches.

import WatchConnectivity
import WatchKit

class AppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        // Activate the WCSession so the watch can talk to the paired iPhone.
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = PhoneConnector.shared
            session.activate()
        }
    }
}
