import SwiftUI
import SwiftData
import WakTrainerDesignSystem

@main
struct CoufunchApp: App {
    var body: some Scene {
        WindowGroup {
            CoufunchRootView()
                .tint(CoufunchColor.primary)
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
    @StateObject private var holidayStore = KoreanPublicHolidayStore()
    @AppStorage("paydayReminderPromptAnswered") private var promptAnswered = false
    @AppStorage("paydayRemindersEnabled") private var remindersEnabled = false
    @State private var askReminders = false
    @State private var isShowingSplash = true

    var body: some View {
        ZStack {
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
                            loadedYears: holidayStore.loadedYears
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

private struct AppSwitcherPrivacyCover: View {
    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.039, blue: 0.047)

            Image("SplashIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
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

                Image("SplashIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: logoSize, height: logoSize)
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

                // Enter from beyond the left edge and land in the middle.
                withAnimation(.easeOut(duration: 0.40)) {
                    logoX = 0
                }
                guard await pause(420) else { return }

                // Three increasingly smaller bounces in the center.
                for height: CGFloat in [54, 34, 18] {
                    withAnimation(.easeOut(duration: 0.13)) {
                        logoY = -height
                    }
                    guard await pause(130) else { return }
                    withAnimation(.easeIn(duration: 0.15)) {
                        logoY = 0
                    }
                    guard await pause(170) else { return }
                }

                // The logo exits completely offscreen to the right.
                withAnimation(.easeIn(duration: 0.36)) {
                    logoX = outside
                }
                guard await pause(380) else { return }

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
