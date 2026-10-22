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
    @Query private var workplaces: [Workplace]
    @AppStorage("paydayReminderPromptAnswered") private var promptAnswered = false
    @AppStorage("paydayRemindersEnabled") private var remindersEnabled = false
    @State private var askReminders = false

    var body: some View {
        Group {
        if workplaces.isEmpty {
            WorkplaceOnboardingView(onComplete: {})
        } else {
            WorkOverviewView()
        }
        }
        .onAppear { askReminders = !promptAnswered && !workplaces.isEmpty }
        .onChange(of: workplaces.count) { _, count in
            if count > 0 && !promptAnswered { askReminders = true }
        }
        .alert("Receive Payday Reminders?", isPresented: $askReminders) {
            Button("Enable Notifications") {
                promptAnswered = true
                Task {
                    remindersEnabled = await PaydayReminderScheduler.requestAuthorization()
                }
            }
            Button("Not Now", role: .cancel) {
                promptAnswered = true
                remindersEnabled = false
            }
        } message: {
            Text("Get a reminder on the next business day after you finish a shift. You can change this later in Settings.")
        }
    }
}
