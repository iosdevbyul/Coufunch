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
        Group {
            if isShowingSplash {
                StartupSplashView()
                    .ignoresSafeArea()
            } else if workplaces.isEmpty {
                WorkplaceOnboardingView(onComplete: {})
            } else {
                WorkOverviewView()
            }
        }
        // Prefetch begins while the splash is visible; slow networks do not block navigation.
        .task {
            await holidayStore.prefetchNearbyYears()
        }
        .task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            isShowingSplash = false
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
