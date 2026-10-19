import SwiftUI
import SwiftData
import TrisCalendarKit
import WakTrainerDesignSystem

struct WorkOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var workBreaks: [WorkBreak]
    @Query private var sessions: [WorkSession]
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
                                ForEach(daySessions.sorted(by: { $0.startAt < $1.startAt })) { session in
                                    HStack {
                                        Text(session.startAt, format: .dateTime.hour().minute())
                                        Text(session.status.rawValue.capitalized).foregroundStyle(.secondary)
                                        Spacer()
                                        Button("Edit") { editingSession = session }
                                        Button(role: .destructive) { pendingDelete = session } label: {
                                            Image(systemName: "trash")
                                        }
                                    }
                                    .font(.subheadline)
                                }
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
