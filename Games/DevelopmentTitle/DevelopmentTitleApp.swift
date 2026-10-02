import GameCore
import GamePlatform
import SwiftUI

@main
struct DevelopmentTitleApp: App {
    var body: some Scene {
        WindowGroup {
            FoundationView()
        }
    }
}

private struct FoundationView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Foundation ready")
                .font(.title)
                .accessibilityIdentifier("foundation.ready")
            Text("iPhone and iPad development title")
                .font(.body)
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
