import SwiftUI
import SwiftData
import WakTrainerDesignSystem

@main
struct CoufunchApp: App {
    var body: some Scene {
        WindowGroup {
            WorkOverviewView()
                .preferredColorScheme(.dark)
                .tint(WakColor.primary)
        }
        .modelContainer(for: [
            Workplace.self,
            WorkSession.self,
            WorkBreak.self,
            IncentiveRule.self,
            ManualIncentive.self
        ])
    }
}
