import SwiftUI
import SwiftData
import TrisCalendarKit
import TrisAdKit
import WakTrainerDesignSystem

struct WorkOverviewView: View {
    @StateObject private var holidayStore = KoreanPublicHolidayStore()
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @Query private var workBreaks: [WorkBreak]
    @Query private var sessions: [WorkSession]
    @Query private var rules: [IncentiveRule]
    @Query private var workplaces: [Workplace]
    @State private var displayedMonth = Date()
    @State private var selectedDate: Date?
    @State private var isSidebarPresented = false
    @State private var financeScreen: WorkFinanceView.Screen?
    @State private var showFinance = false
    @State private var showStatistics = false
    @State private var showSideHustle = false
    @State private var pendingStatisticsNavigation = false
    @State private var managementSection: WorkplaceManagementView.Section?
    @State private var showManagement = false
    @State private var showSettings = false
    @State private var isSessionEntryPresented = false
    @State private var isBulkEntryPresented = false
    @State private var editingSession: WorkSession?
    @State private var pendingDelete: WorkSession?

    private let calendarStyle = CalendarStyle(
        selectedBackgroundColor: CoufunchColor.primary,
        selectedTextColor: .white,
        highlightedBackgroundColor: CoufunchColor.primary.opacity(0.16),
        todayBorderColor: CoufunchColor.primary,
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
            workplaces: workplaces, rules: rules,
            loadedYears: holidayStore.loadedYears
        )
    }

    private struct HolidayDisplay: Identifiable {
        let date: Date
        let name: String
        var id: Date { date }
    }

    private var displayedHolidayDates: [HolidayDisplay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let month = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        return holidayStore.names.compactMap { key, name -> HolidayDisplay? in
            let parts = key.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3, parts[0] == month.year,
                  parts[1] == month.month,
                  let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
                  interval.contains(date) else { return nil }
            return HolidayDisplay(date: date, name: holidayStore.displayName(for: key, locale: locale) ?? name)
        }.sorted { $0.date < $1.date }
    }

    private var holidayDateTextColors: [Date: Color] {
        Dictionary(displayedHolidayDates.map { ($0.date, Color.red) },
                   uniquingKeysWith: { first, _ in first })
    }

    private var holidayDateLabels: [Date: String] {
        Dictionary(displayedHolidayDates.map { ($0.date, $0.name) },
                   uniquingKeysWith: { first, _ in first })
    }

    private var pendingDays: Set<Date> {
        let calendar = Calendar.current
        return Set(sessions.filter { $0.status != .completed }.map {
            calendar.startOfDay(for: $0.startAt)
        }).subtracting(completedDays)
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
                        outlinedDates: pendingDays,
                        dateTextColors: holidayDateTextColors,
                        dateLabels: holidayDateLabels,
                        configuration: calendarConfiguration,
                        style: calendarStyle
                    )

                    if let error = holidayStore.errorMessage {
                        Text(LocalizedStringKey(error)).font(.caption).foregroundStyle(.orange)
                    }

                    HStack {
                        Button("Add Work Session") { isSessionEntryPresented = true }
                            .buttonStyle(.borderedProminent)
                        Button {
                            isBulkEntryPresented = true
                        } label: {
                            Label("여러 날짜 추가", systemImage: "calendar.badge.plus")
                        }
                        .buttonStyle(.bordered)
                    }

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
                                if let holidayName = holidayName(for: selectedDate) {
                                    LabeledContent("Public Holiday", value: holidayName)
                                        .font(.subheadline)
                                        .foregroundStyle(CoufunchColor.textPrimary)
                                }
                                Text(String(format: String(localized: "%d session(s)"), daySessions.count))
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
                                            Text(LocalizedStringKey(session.status.rawValue.capitalized)).font(.caption).foregroundStyle(.secondary)
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
            .task(id: Calendar.current.component(.year, from: displayedMonth)) {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
                await holidayStore.load(year: calendar.component(.year, from: displayedMonth))
            }
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
            .sheet(isPresented: $isBulkEntryPresented) {
                BulkWorkSessionEntryView(initialMonth: displayedMonth)
            }
            .sheet(isPresented: $isSessionEntryPresented) {
                WorkSessionEntryView(date: selectedDate ?? Date()) {
                    isSessionEntryPresented = false
                }
            }
            .navigationDestination(isPresented: $showFinance) {
                if let financeScreen { WorkFinanceView(screen: financeScreen) }
            }
            .navigationDestination(isPresented: $showStatistics) {
                MonthlyPayStatisticsView()
            }
            .navigationDestination(isPresented: $showSideHustle) {
                TrisSideHustleView(pointsProvider: UnconfiguredRewardPointsProvider())
            }
            .navigationDestination(isPresented: $showSettings) {
                CoufunchSettingsView()
            }
            .navigationDestination(isPresented: $showManagement) {
                if let managementSection { WorkplaceManagementView(section: managementSection) }
            }
            .sheet(isPresented: $isSidebarPresented, onDismiss: {
                if pendingStatisticsNavigation {
                    pendingStatisticsNavigation = false
                    showStatistics = true
                }
            }) {
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
                            pendingStatisticsNavigation = true
                            isSidebarPresented = false
                        } label: {
                            Label("통계", systemImage: "chart.bar.xaxis")
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
                        Button {
                            isSidebarPresented = false
                            showSideHustle = true
                        } label: {
                            Label("부업", systemImage: "play.rectangle")
                        }
                        Button {
                            isSidebarPresented = false
                            showSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
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
    private func holidayName(for date: Date) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            return nil
        }
        return holidayStore.displayName(for: String(format: "%04d-%02d-%02d", year, month, day), locale: locale)
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
