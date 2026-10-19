import SwiftUI
import SwiftData
import WakTrainerDesignSystem

@main
struct CoufunchApp: App {
    var body: some Scene {
        WindowGroup {
            CoufunchRootView()
                .preferredColorScheme(.dark)
                .tint(WakColor.primary)
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

    var body: some View {
        if workplaces.isEmpty {
            WorkplaceOnboardingView(onComplete: {})
        } else {
            WorkOverviewView()
        }
    }
}
