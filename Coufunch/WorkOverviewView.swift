import SwiftUI
import SwiftData
import TrisCalendarKit
import WakTrainerDesignSystem

struct WorkOverviewView: View {
    @Query private var sessions: [WorkSession]
    @State private var displayedMonth = Date()
    @State private var selectedDate: Date?
    @State private var isSidebarPresented = false
    @State private var isSessionEntryPresented = false

    private let calendarConfiguration = CalendarConfiguration(
        locale: .system,
        timeZone: .system,
        weekStart: .sunday
    )

    private var completedDays: Set<Date> {
        let calendar = Calendar.current
        return Set(sessions.filter { $0.status == .completed }.map {
            calendar.startOfDay(for: $0.startAt)
        })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WakSpacing.large) {
                    MonthCalendarView(
                        displayedMonth: $displayedMonth,
                        selectedDate: $selectedDate,
                        highlightedDates: completedDays,
                        configuration: calendarConfiguration
                    )

                    Button("Add Work Session") { isSessionEntryPresented = true }
                        .buttonStyle(.borderedProminent)

                    WakCard {
                        VStack(alignment: .leading, spacing: WakSpacing.medium) {
                            Text("Work Sessions")
                                .font(WakTypography.screenTitle)
                                .foregroundStyle(WakColor.textPrimary)

                            if let selectedDate {
                                let daySessions = sessions.filter {
                                    Calendar.current.isDate($0.startAt, inSameDayAs: selectedDate)
                                }
                                Text(selectedDate, format: .dateTime.year().month().day())
                                    .foregroundStyle(WakColor.textPrimary)
                                Text("\(daySessions.count) session(s)")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Select a date to view work sessions.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(WakSpacing.large)
            }
            .background(WakColor.background)
            .navigationTitle("Work Overview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isSidebarPresented = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                    .accessibilityLabel("Open menu")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        displayedMonth = Date()
                        selectedDate = nil
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh overview")
                }
            }
            .sheet(isPresented: $isSessionEntryPresented) {
                WorkSessionEntryView(date: selectedDate ?? Date()) {
                    isSessionEntryPresented = false
                }
            }
            .sheet(isPresented: $isSidebarPresented) {
                NavigationStack {
                    List {
                        Label("Work Overview", systemImage: "calendar")
                        Label("Pay & Allowances", systemImage: "wallet.bifold")
                        Label("Work Strategy", systemImage: "chart.bar")
                        Label("Workplaces", systemImage: "building.2")
                        Label("Incentives", systemImage: "slider.horizontal.3")
                        Label("Settings", systemImage: "gearshape")
                    }
                    .scrollContentBackground(.hidden)
                    .background(WakColor.background)
                    .navigationTitle("Coufunch")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { isSidebarPresented = false }
                        }
                    }
                }
                .presentationDetents([.large])
            }
        }
    }
}

#Preview {
    WorkOverviewView()
        .modelContainer(for: [WorkSession.self], inMemory: true)
}
