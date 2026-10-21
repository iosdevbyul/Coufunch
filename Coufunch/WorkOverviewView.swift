import SwiftUI
import SwiftData
import TrisCalendarKit
import WakTrainerDesignSystem

struct WorkOverviewView: View {
    @StateObject private var holidayStore = KoreanPublicHolidayStore()
    @Environment(\.modelContext) private var modelContext
    @Query private var workBreaks: [WorkBreak]
    @Query private var sessions: [WorkSession]
    @Query private var workplaces: [Workplace]
    @State private var displayedMonth = Date()
    @State private var selectedDate: Date?
    @State private var isSidebarPresented = false
    @State private var financeScreen: WorkFinanceView.Screen?
    @State private var showFinance = false
    @State private var managementSection: WorkplaceManagementView.Section?
    @State private var showManagement = false
    @State private var isSessionEntryPresented = false
    @State private var editingSession: WorkSession?
    @State private var pendingDelete: WorkSession?

    private let calendarStyle = CalendarStyle(
        weekdaySaturdayColor: .blue,
        weekdaySundayColor: .red
    )

    private let calendarConfiguration = CalendarConfiguration(
        locale: .system,
        timeZone: .system,
        weekStart: .sunday
    )

    private var reminderSyncKey: String {
        sessions.sorted { $0.id.uuidString < $1.id.uuidString }
            .map { "\($0.id):\($0.startAt.timeIntervalSince1970):\($0.statusRaw)" }
            .joined(separator: "|")
    }

    private func refreshPaydayReminders() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let year = calendar.component(.year, from: Date())
        await holidayStore.load(year: year)
        await holidayStore.load(year: year + 1)
        await PaydayReminderScheduler.synchronize(
            sessions: sessions, holidays: holidayStore.dates,
            loadedYears: holidayStore.loadedYears
        )
    }

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
                        configuration: calendarConfiguration,
                        style: calendarStyle
                    )

                    Button("Enable Payday Reminders") {
                        Task {
                            if await PaydayReminderScheduler.requestAuthorization() {
                                await refreshPaydayReminders()
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Receive a payday reminder at 10 AM on the next Korean business day after completed work.")

                    Button("Add Work Session") { isSessionEntryPresented = true }
                        .buttonStyle(.borderedProminent)

                    CoufunchCard {
                        VStack(alignment: .leading, spacing: WakSpacing.medium) {
                            Text("Work Sessions")
                                .font(WakTypography.screenTitle)
                                .foregroundStyle(CoufunchColor.textPrimary)

                            if let selectedDate {
                                let daySessions = sessions.filter {
                                    Calendar.current.isDate($0.startAt, inSameDayAs: selectedDate)
                                }
                                Text(selectedDate, format: .dateTime.year().month().day())
                                    .foregroundStyle(CoufunchColor.textPrimary)
                                Text("\(daySessions.count) session(s)")
                                    .foregroundStyle(.secondary)
                                if daySessions.isEmpty {
                                    Text("No shifts recorded for this day.").font(.subheadline).foregroundStyle(.secondary)
                                }
                                ForEach(daySessions.sorted(by: { $0.startAt < $1.startAt })) { session in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(workplaces.first(where: { $0.id == session.workplaceID })?.name ?? "Workplace").font(.headline)
                                            Text(session.startAt, format: .dateTime.hour().minute())
                                                .font(.caption.monospacedDigit())
                                            Text(session.status.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button("Edit") { editingSession = session }
                                            .accessibilityLabel("Edit work session")
                                        Button(role: .destructive) { pendingDelete = session } label: {
                                            Image(systemName: "trash").frame(minWidth: 44, minHeight: 44)
                                        }
                                        .accessibilityLabel("Delete work session")
                                    }
                                    .font(.subheadline)
                                }
                            } else {
                                Text("Select a date to view work sessions.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(WakSpacing.large)
            }
            .background(CoufunchColor.background)
            .task(id: reminderSyncKey) { await refreshPaydayReminders() }
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
            .sheet(item: $editingSession) { session in
                WorkSessionEntryView(date: session.startAt, editingSession: session) {
                    editingSession = nil
                }
            }
            .alert("Delete Work Session?", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )) {
                Button("Delete", role: .destructive) { deletePendingSession() }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("This also removes the session's break records.")
            }
            .sheet(isPresented: $isSessionEntryPresented) {
                WorkSessionEntryView(date: selectedDate ?? Date()) {
                    isSessionEntryPresented = false
                }
            }
            .navigationDestination(isPresented: $showFinance) {
                if let financeScreen { WorkFinanceView(screen: financeScreen) }
            }
            .navigationDestination(isPresented: $showManagement) {
                if let managementSection { WorkplaceManagementView(section: managementSection) }
            }
            .sheet(isPresented: $isSidebarPresented) {
                NavigationStack {
                    List {
                        Label("Work Overview", systemImage: "calendar")
                        Button {
                            financeScreen = .pay
                            isSidebarPresented = false
                            showFinance = true
                        } label: {
                            Label("Pay & Allowances", systemImage: "wallet.bifold")
                        }
                        Button {
                            financeScreen = .strategy
                            isSidebarPresented = false
                            showFinance = true
                        } label: {
                            Label("Work Strategy", systemImage: "chart.bar")
                        }
                        Button {
                            managementSection = .workplaces
                            isSidebarPresented = false
                            showManagement = true
                        } label: {
                            Label("Workplaces", systemImage: "building.2")
                        }
                        Button {
                            managementSection = .incentives
                            isSidebarPresented = false
                            showManagement = true
                        } label: {
                            Label("Incentives", systemImage: "slider.horizontal.3")
                        }
                        Label("Settings", systemImage: "gearshape")
                    }
                    .scrollContentBackground(.hidden)
                    .background(CoufunchColor.background)
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
    private func deletePendingSession() {
        guard let session = pendingDelete else { return }
        pendingDelete = nil
        for rest in workBreaks where rest.sessionID == session.id {
            modelContext.delete(rest)
        }
        modelContext.delete(session)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
        }
    }
}

#Preview {
    WorkOverviewView()
        .modelContainer(for: [WorkSession.self], inMemory: true)
}
