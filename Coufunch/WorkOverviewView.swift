import SwiftUI
import TrisCalendarKit

struct WorkOverviewView: View {
    @State private var displayedMonth = Date()
    @State private var selectedDate: Date?
    @State private var isSidebarPresented = false

    private let calendarConfiguration = CalendarConfiguration(
        locale: .system,
        timeZone: .system,
        weekStart: .sunday
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    MonthCalendarView(
                        displayedMonth: $displayedMonth,
                        selectedDate: $selectedDate,
                        configuration: calendarConfiguration
                    )

                    if let selectedDate {
                        Text(selectedDate, format: .dateTime.year().month().day())
                            .font(.headline)
                    } else {
                        Text("Select a date to view work sessions.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
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
}
