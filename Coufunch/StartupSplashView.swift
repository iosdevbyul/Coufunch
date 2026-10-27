import SwiftUI

/// Displayed after iOS LaunchScreen while startup data is prefetched.
struct StartupSplashView: View {
    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.039, blue: 0.047)

            Image("SplashIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
        }
        .accessibilityHidden(true)
    }
}
