// Aanchal Watch App — Phone Connector
//
// Manages WCSession communication between the Watch and the paired iPhone.
// Sends "SOS" / "CANCEL_SOS" actions (with user UID) and receives status
// acknowledgements. Also receives USER_SYNC profile data from the iPhone.

import Foundation
import WatchConnectivity

class PhoneConnector: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = PhoneConnector()

    @Published var sosActive = false
    @Published var isReachable = false

    // Synced user profile from the iPhone
    @Published var userName: String = ""
    @Published var userUid: String = ""
    @Published var userEmail: String = ""
    @Published var isUserSynced: Bool = false

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Send SOS trigger to the iPhone Flutter app (includes user UID).
    func triggerSOS() {
        sosActive = true
        sendPayload(["action": "SOS", "uid": userUid])
    }

    /// Cancel the active SOS.
    func cancelSOS() {
        sosActive = false
        sendPayload(["action": "CANCEL_SOS", "uid": userUid])
    }

    /// Ask the iPhone to send us the current user profile.
    func requestUser() {
        sendPayload(["action": "REQUEST_USER"])
    }

    // MARK: - Sending

    private func sendPayload(_ payload: [String: Any]) {
        guard WCSession.default.isReachable else {
            print("[AanchalWatch] iPhone not reachable — using transferUserInfo")
            WCSession.default.transferUserInfo(payload)
            return
        }

        WCSession.default.sendMessage(
            payload,
            replyHandler: { reply in
                print("[AanchalWatch] Reply: \(reply)")
            },
            errorHandler: { error in
                print("[AanchalWatch] Send error: \(error.localizedDescription)")
            }
        )
    }

    // MARK: - Receiving user profile

    private func handleUserSync(_ data: [String: Any]) {
        DispatchQueue.main.async {
            self.userUid = data["uid"] as? String ?? ""
            self.userName = data["name"] as? String ?? ""
            self.userEmail = data["email"] as? String ?? ""
            self.isUserSynced = !self.userUid.isEmpty
            print("[AanchalWatch] User synced: \(self.userName) (\(self.userUid))")
        }
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
        if let error = error {
            print("[AanchalWatch] Activation error: \(error.localizedDescription)")
        } else {
            print("[AanchalWatch] WCSession activated — state: \(activationState.rawValue)")
            // Check if there's already a synced application context.
            let ctx = session.receivedApplicationContext
            if let action = ctx["action"] as? String, action == "USER_SYNC" {
                handleUserSync(ctx)
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
        print("[AanchalWatch] Reachability: \(session.isReachable)")
        // When iPhone becomes reachable and we don't have a user, ask for one.
        if session.isReachable && !isUserSynced {
            requestUser()
        }
    }

    /// Receive real-time messages from the iPhone.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let action = message["action"] as? String, action == "USER_SYNC" {
            handleUserSync(message)
            return
        }
        DispatchQueue.main.async {
            if let status = message["status"] as? String {
                print("[AanchalWatch] Status: \(status)")
                if status == "SOS_ACTIVATED" {
                    self.sosActive = true
                } else if status == "SOS_DEACTIVATED" {
                    self.sosActive = false
                }
            }
        }
    }

    /// Receive application context updates (persisted, works even when watch app isn't running).
    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        if let action = applicationContext["action"] as? String, action == "USER_SYNC" {
            handleUserSync(applicationContext)
        }
    }
}
