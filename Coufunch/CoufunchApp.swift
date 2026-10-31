import SwiftUI
import SwiftData
import WakTrainerDesignSystem

@main
struct CoufunchApp: App {
    var body: some Scene {
        WindowGroup {
            AppCaptureProtectedView {
                CoufunchRootView()
                    .tint(CoufunchColor.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                // Fill the window's safe-area margins behind the secure host.
                // The animated splash curtain must still slide independently.
                Color(red: 0.035, green: 0.039, blue: 0.047)
                    .ignoresSafeArea()
            }
        }
        .modelContainer(for: [
            Workplace.self,
            WorkplacePaySettings.self,
            WorkSession.self,
            WorkBreak.self,
            IncentiveRule.self,
            ManualIncentive.self,
            ReceivedPayRecord.self
        ])
    }
}

private struct CoufunchRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query private var workplaces: [Workplace]
    @Query private var sessions: [WorkSession]
    @Query private var rules: [IncentiveRule]
    @Query private var breaks: [WorkBreak]
    @Query private var paySettings: [WorkplacePaySettings]
    @Query private var receivedPay: [ReceivedPayRecord]
    @StateObject private var holidayStore = KoreanPublicHolidayStore()
    @AppStorage("paydayReminderPromptAnswered") private var promptAnswered = false
    @AppStorage("paydayRemindersEnabled") private var remindersEnabled = false
    @State private var askReminders = false
    @State private var isShowingSplash = true

    var body: some View {
        ZStack {
            // Cover any transparency around the protected SwiftUI host while
            // keeping the current splash animation and app navigation intact.
            Color(red: 0.035, green: 0.039, blue: 0.047)
                .ignoresSafeArea()

            Group {
                if workplaces.isEmpty {
                    WorkplaceOnboardingView(onComplete: {})
                } else {
                    WorkOverviewView()
                }
            }

            if isShowingSplash {
                StartupSplashView {
                    isShowingSplash = false
                }
                .ignoresSafeArea()
                .zIndex(2)
            }
        }
        // Prefetch begins while the splash is visible; slow networks do not block navigation.
        .task {
            await holidayStore.prefetchNearbyYears()
        }
        .onChange(of: isShowingSplash) { _, showing in
            if !showing && !promptAnswered && !workplaces.isEmpty {
                askReminders = true
            }
        }
        .onChange(of: workplaces.count) { _, count in
            if !isShowingSplash && count > 0 && !promptAnswered {
                askReminders = true
            }
        }
        .alert("Receive Payday Reminders?", isPresented: $askReminders) {
            Button("Enable Notifications") {
                promptAnswered = true
                Task {
                    remindersEnabled = await PaydayReminderScheduler.requestAuthorization()
                    if remindersEnabled {
                        var calendar = Calendar(identifier: .gregorian)
                        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
                        let year = calendar.component(.year, from: Date())
                        await holidayStore.load(year: year)
                        await holidayStore.load(year: year + 1)
                        await PaydayReminderScheduler.synchronize(
                            sessions: sessions, holidays: holidayStore.dates,
                            workplaces: workplaces, rules: rules,
                            loadedYears: holidayStore.loadedYears,
                            breaks: breaks, paySettings: paySettings, receivedPay: receivedPay
                        )
                    }
                }
            }
            Button("Not Now", role: .cancel) {
                promptAnswered = true
                remindersEnabled = false
            }
        } message: {
            Text("Get a reminder on the next business day after you finish a shift. You can change this later in Settings.")
        }
        .overlay {
            if scenePhase != .active {
                AppSwitcherPrivacyCover()
                    .ignoresSafeArea()
                    .transition(.identity)
                    .zIndex(1)
            }
        }
    }
}

/// Shared treatment for the opaque SplashIcon source. The dark square should
/// not become visible on either the moving startup logo or the privacy cover.
private struct SeamlessSplashLogo: View {
    let size: CGFloat

    var body: some View {
        Image("SplashIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .blendMode(.screen)
            .mask {
                RadialGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: 0.56),
                        .init(color: .clear, location: 0.74)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.72
                )
            }
    }
}

private struct AppSwitcherPrivacyCover: View {
    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.039, blue: 0.047)

            SeamlessSplashLogo(size: 200)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(true)
    }
}

import SwiftUI

/// Displayed after the static iOS LaunchScreen. The home screen is already
/// underneath; the closing curtain reveals it from right to left.
private struct StartupSplashView: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoX: CGFloat = -1
    @State private var logoY: CGFloat = 0
    @State private var curtainX: CGFloat = 0
    @State private var started = false

    private let backgroundColor = Color(red: 0.035, green: 0.039, blue: 0.047)
    private let logoSize: CGFloat = 200

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let outside = screenWidth / 2 + logoSize

            ZStack {
                backgroundColor

                SeamlessSplashLogo(size: logoSize)
                    .offset(x: logoX == -1 ? -outside : logoX, y: logoY)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .offset(x: curtainX)
            .task {
                guard !started else { return }
                started = true

                if reduceMotion {
                    // Respect accessibility settings without requiring precise motion.
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    onFinished()
                    return
                }

                // The logo travels left-to-right THROUGH three bounces.
                // Each landing advances along the screen, never in place.
                let landings: [CGFloat] = [
                    -screenWidth * 0.25,
                    0,
                    screenWidth * 0.25
                ]
                let heights: [CGFloat] = [64, 52, 38]
                let launchX = -outside
                logoX = launchX

                for index in landings.indices {
                    let startX = index == 0 ? launchX : landings[index - 1]
                    let landingX = landings[index]
                    // Rise while moving halfway to the next landing.
                    withAnimation(.easeOut(duration: 0.20)) {
                        logoX = (startX + landingX) / 2
                        logoY = -heights[index]
                    }
                    guard await pause(210) else { return }

                    // Fall and advance to the next rightward position.
                    withAnimation(.easeIn(duration: 0.18)) {
                        logoX = landingX
                        logoY = 0
                    }
                    guard await pause(200) else { return }
                }

                // Exit completely off the right edge after the third landing.
                withAnimation(.easeIn(duration: 0.34)) {
                    logoX = outside
                }
                guard await pause(360) else { return }

                // Slide the entire dark splash offscreen to the left.
                withAnimation(.easeInOut(duration: 0.42)) {
                    curtainX = -screenWidth
                }
                guard await pause(440) else { return }
                onFinished()
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(true)
    }

    private func pause(_ milliseconds: Int) async -> Bool {
        do {
            try await Task.sleep(for: .milliseconds(milliseconds))
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}
