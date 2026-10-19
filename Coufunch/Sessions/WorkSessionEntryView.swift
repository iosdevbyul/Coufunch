import SwiftUI
import SwiftData
import WakTrainerDesignSystem

struct WorkSessionEntryView: View {
    let date: Date
    let onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Workplace.name) private var workplaces: [Workplace]
    @Query private var settings: [WorkplacePaySettings]

    @State private var workplaceID: UUID?
    @State private var status: WorkSessionStatus = .completed
    @State private var work = TimelineRange(start: 1140, end: 1680)
    @State private var breaks = [TimelineRange(start: 1320, end: 1380)]
    @State private var overrideAmount = ""
    @State private var errorMessage: String?

    private var currentSettings: WorkplacePaySettings? {
        settings.first { $0.workplaceID == workplaceID }
    }

    private var fixedPay: Decimal? {
        guard let settings = currentSettings else { return nil }
        guard settings.payMode == .fixedDaily else { return nil }
        if !overrideAmount.isEmpty { return Decimal(string: overrideAmount) }
        return settings.fixedDailyPay
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WakSpacing.large) {
                    Text(date, format: .dateTime.year().month().day())
                        .font(WakTypography.screenTitle)
                    Picker("Workplace", selection: $workplaceID) {
                        Text("Select a workplace").tag(Optional<UUID>.none)
                        ForEach(workplaces) { workplace in
                            Text(workplace.name).tag(Optional(workplace.id))
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Status", selection: $status) {
                        Text("Applied").tag(WorkSessionStatus.applied)
                        Text("Confirmed").tag(WorkSessionStatus.confirmed)
                        Text("Completed").tag(WorkSessionStatus.completed)
                    }
                    .pickerStyle(.segmented)

                    WorkTimelineEditor(work: $work, breaks: $breaks)

                    if currentSettings?.payMode == .fixedDaily {
                        TextField("Daily pay override (optional)", text: $overrideAmount)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    }

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.footnote)
                    }
                    Button("Save Work Session") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(workplaceID == nil)
                }
                .padding(WakSpacing.medium)
            }
            .background(WakColor.background)
            .navigationTitle("Add Work Session")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel", action: onSaved)
                }
            }
        }
        .tint(WakColor.primary)
        .preferredColorScheme(.dark)
        .onAppear { workplaceID = workplaceID ?? workplaces.first?.id }
    }

    private func save() {
        guard let workplaceID,
              let settings = currentSettings,
              let midnight = Calendar.current.dateInterval(of: .day, for: date)?.start,
              work.end > work.start else {
            errorMessage = "Choose a workplace and a valid time range."
            return
        }
        let start = midnight.addingTimeInterval(TimeInterval(work.start * 60))
        let end = midnight.addingTimeInterval(TimeInterval(work.end * 60))
        let fixed = fixedPay
        if settings.payMode == .fixedDaily && (fixed == nil || fixed! < 0) {
            errorMessage = "Enter a valid daily wage."
            return
        }
        let hourlyRate: Decimal?
        switch settings.payMode {
        case .fixedDaily: hourlyRate = nil
        case .customHourly: hourlyRate = settings.customHourlyRate
        case .minimumHourly:
            // 2026 statutory minimum; later phases will provide a dated rate table.
            hourlyRate = 10_320
        }
        if settings.payMode != .fixedDaily && (hourlyRate == nil || hourlyRate! <= 0) {
            errorMessage = "Hourly rate is missing."
            return
        }

        let session = WorkSession(
            workplaceID: workplaceID, startAt: start, endAt: end, status: status,
            payMode: settings.payMode,
            hourlyRateSnapshot: hourlyRate,
            fixedDailyPaySnapshot: fixed
        )
        context.insert(session)
        for rest in breaks {
            guard rest.start >= work.start, rest.end <= work.end, rest.end > rest.start else {
                context.rollback()
                errorMessage = "Break times must be within the shift."
                return
            }
            context.insert(WorkBreak(
                sessionID: session.id,
                startAt: midnight.addingTimeInterval(TimeInterval(rest.start * 60)),
                endAt: midnight.addingTimeInterval(TimeInterval(rest.end * 60))
            ))
        }
        do {
            try context.save()
            onSaved()
        } catch {
            context.rollback()
            errorMessage = "Could not save the session."
        }
    }
}
