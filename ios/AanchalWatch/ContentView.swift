// Aanchal Watch App — Main UI
//
// Full-screen SOS button with:
//   • Tap to trigger SOS
//   • watchOS 10+ double-tap finger gesture via .handGestureShortcut(.primaryAction)
//   • Haptic feedback on activation
//   • Connected user display & user-gated SOS

import SwiftUI
import WatchKit

struct ContentView: View {
    @StateObject private var connector = PhoneConnector.shared
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            (connector.sosActive ? Color.red : Color.black)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                // Show connected user or "Not connected"
                if connector.isUserSynced {
                    HStack(spacing: 6) {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text(connector.userName)
                            .font(.caption2)
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .padding(.top, 4)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "person.slash")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("Not connected")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 4)
                }

                // Status text
                Text(connector.sosActive ? "SOS ACTIVE" : "Aanchal")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                // SOS Button
                Button(action: { handleSOSTap() }) {
                    ZStack {
                        Circle()
                            .fill(connector.sosActive ? Color.white : Color.red)
                            .frame(width: 120, height: 120)
                            .scaleEffect(isAnimating ? 1.1 : 1.0)
                            .animation(
                                connector.sosActive
                                    ? .easeInOut(duration: 0.6)
                                        .repeatForever(autoreverses: true)
                                    : .default,
                                value: isAnimating
                            )

                        Text(connector.sosActive ? "CANCEL" : "SOS")
                            .font(.system(size: 28, weight: .black))
                            .foregroundColor(connector.sosActive ? .red : .white)
                    }
                }
                .buttonStyle(.plain)
                .handGestureShortcut(.primaryAction)
                .disabled(!connector.isUserSynced)
                .opacity(connector.isUserSynced ? 1.0 : 0.4)

                Spacer()

                // Connectivity status
                HStack(spacing: 4) {
                    Circle()
                        .fill(connector.isReachable ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(connector.isReachable ? "iPhone connected" : "iPhone not reachable")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 4)
            }
        }
        .onChange(of: connector.sosActive) { _, active in
            isAnimating = active
        }
        .onAppear {
            // If no user is synced yet, ask the iPhone to send the profile.
            if !connector.isUserSynced {
                connector.requestUser()
            }
        }
    }

    private func handleSOSTap() {
        guard connector.isUserSynced else { return }

        if connector.sosActive {
            connector.cancelSOS()
            WKInterfaceDevice.current().play(.stop)
        } else {
            connector.triggerSOS()
            WKInterfaceDevice.current().play(.notification)
        }
    }
}

#Preview {
    ContentView()
}
