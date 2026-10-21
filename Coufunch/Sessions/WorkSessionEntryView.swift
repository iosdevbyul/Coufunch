import SwiftUI
import SwiftData
import WakTrainerDesignSystem

struct WorkSessionEntryView: View {
    let date: Date
    var editingSession: WorkSession? = nil
    let onSaved: () -> Void

    @StateObject private var holidayStore = KoreanPublicHolidayStore()
    @Environment(\.modelContext) private var context
    @Query(sort: \Workplace.name) private var workplaces: [Workplace]
    @Query private var settings: [WorkplacePaySettings]
    @Query private var storedBreaks: [WorkBreak]

    @State private var workplaceID: UUID?
    @State private var status: WorkSessionStatus = .completed
    @State private var work = TimelineRange(start: 1140, end: 1680)
    @State private var breaks = [TimelineRange(start: 1320, end: 1380)]
    @State private var overrideAmount = ""
    @State private var errorMessage: String?

    private var currentSettings: WorkplacePaySettings? {
        settings.first { $0.workplaceID == workplaceID }
    }

    private var holidayMinutes: Int {
        guard let midnight = Calendar.current.dateInterval(of: .day, for: date)?.start else { return 0 }
        let start = midnight.addingTimeInterval(Double(work.start * 60))
        let end = midnight.addingTimeInterval(Double(work.end * 60))
        var cursor = Calendar.current.startOfDay(for: start)
        var total = 0
        while cursor < end {
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: cursor) else { break }
            if holidayStore.isPublicHoliday(cursor) {
                let overlapStart = max(start, cursor)
                let overlapEnd = min(end, next)
                if overlapEnd > overlapStart {
                    total += Int(overlapEnd.timeIntervalSince(overlapStart) / 60)
                    for interval in breaks {
                        let from = midnight.addingTimeInterval(Double(interval.start * 60))
                        let to = midnight.addingTimeInterval(Double(interval.end * 60))
                        total -= max(0, Int(min(overlapEnd, to).timeIntervalSince(max(overlapStart, from)) / 60))
                    }
                }
            }
            cursor = next
        }
        return max(0, total)
    }

    private var payPreview: PayResult? {
        guard let workplaceID,
              let preferences = currentSettings,
              let midnight = Calendar.current.dateInterval(of: .day, for: date)?.start else { return nil }
        let start = midnight.addingTimeInterval(TimeInterval(work.start * 60))
        let end = midnight.addingTimeInterval(TimeInterval(work.end * 60))
        let mode = editingSession?.payMode ?? preferences.payMode
        let hourly: Decimal?
        switch mode {
        case .minimumHourly:
            hourly = editingSession?.hourlyRateSnapshot ?? MinimumWageSchedule.hourlyRate(for: start)
        case .customHourly:
            hourly = editingSession?.hourlyRateSnapshot ?? preferences.customHourlyRate
        case .fixedDaily:
            hourly = nil
        }
        let draft = WorkSession(workplaceID: workplaceID, startAt: start, endAt: end,
                                status: status, payMode: mode, hourlyRateSnapshot: hourly,
                                fixedDailyPaySnapshot: fixedPay)
        let rests = breaks.map {
            WorkBreak(sessionID: draft.id,
                      startAt: midnight.addingTimeInterval(TimeInterval($0.start * 60)),
                      endAt: midnight.addingTimeInterval(TimeInterval($0.end * 60)))
        }
        return try? WorkPayCalculator.calculate(session: draft, breaks: rests,
                                                  calendar: .current,
                                                  nightPremiumEnabled: editingSession?.nightPremiumSnapshot ?? preferences.nightPremiumEnabled,
                                                  overtimePremiumEnabled: editingSession?.overtimePremiumSnapshot ?? preferences.overtimePremiumEnabled,
                                                  holidayPaidMinutes: holidayMinutes)
    }

    private func currency(_ amount: Decimal) -> String {
        NSDecimalNumber(decimal: amount).intValue.formatted(.currency(code: "KRW"))
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

                    if (editingSession?.payMode ?? currentSettings?.payMode) == .fixedDaily {
                        TextField("Daily pay override (optional)", text: $overrideAmount)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    }

                    if let preview = payPreview {
                        WakCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Estimated Gross Pay").font(.headline)
                                LabeledContent("Paid work", value: "\(preview.workedMinutes / 60)h \(preview.workedMinutes % 60)m")
                                LabeledContent("Night work", value: "\(preview.nightMinutes / 60)h \(preview.nightMinutes % 60)m")
                                LabeledContent("Daily overtime", value: "\(preview.overtimeMinutes / 60)h \(preview.overtimeMinutes % 60)m")
                                LabeledContent("Base pay", value: currency(preview.basePay))
                                LabeledContent("Night premium", value: currency(preview.nightPremium))
                                LabeledContent("Overtime premium", value: currency(preview.overtimePremium))
                                LabeledContent("Holiday premium", value: currency(preview.holidayPremium))
                                Text(currency(preview.total))
                                    .font(.title2.bold())
                                    .foregroundStyle(WakColor.primary)
                                Text("Before deductions. Overtime estimates assume eligible employment and daily work exceeding 8 paid hours; weekly and holiday rules are not included.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let holidayError = holidayStore.errorMessage {
                        Text(holidayError).font(.caption).foregroundStyle(.orange)
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
            .navigationTitle(editingSession == nil ? "Add Work Session" : "Edit Work Session")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel", action: onSaved)
                }
            }
        }
        .tint(WakColor.primary)
        .preferredColorScheme(.dark)
        .onAppear(perform: loadExisting)
        .task(id: Calendar.current.component(.year, from: date)) {
            let year = Calendar.current.component(.year, from: date)
            await holidayStore.load(year: year)
            await holidayStore.load(year: year + 1)
        }
    }

    private func loadExisting() {
        guard let session = editingSession else {
            workplaceID = workplaces.first?.id
            return
        }
        workplaceID = session.workplaceID
        status = session.status
        let startOfDay = Calendar.current.startOfDay(for: session.startAt)
        let startMinute = Int(session.startAt.timeIntervalSince(startOfDay) / 60)
        let endMinute = Int((session.endAt ?? session.startAt).timeIntervalSince(startOfDay) / 60)
        work = TimelineRange(start: startMinute, end: endMinute)
        breaks = storedBreaks.filter { $0.sessionID == session.id }.map {
            TimelineRange(start: Int($0.startAt.timeIntervalSince(startOfDay) / 60),
                          end: Int($0.endAt.timeIntervalSince(startOfDay) / 60))
        }
        if session.payMode == .fixedDaily, let amount = session.fixedDailyPaySnapshot {
            overrideAmount = NSDecimalNumber(decimal: amount).stringValue
        }
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
        let fixed = editingSession?.payMode == .fixedDaily ? (Decimal(string: overrideAmount) ?? editingSession?.fixedDailyPaySnapshot) : fixedPay
        let selectedMode = editingSession?.payMode ?? settings.payMode
        if selectedMode == .fixedDaily && (fixed == nil || fixed! < 0) {
            errorMessage = "Enter a valid daily wage."
            return
        }
        let hourlyRate: Decimal?
        switch selectedMode {
        case .fixedDaily: hourlyRate = nil
        case .customHourly: hourlyRate = editingSession?.hourlyRateSnapshot ?? settings.customHourlyRate
        case .minimumHourly:
            hourlyRate = editingSession?.hourlyRateSnapshot ?? MinimumWageSchedule.hourlyRate(for: start)
        }
        if selectedMode != .fixedDaily && (hourlyRate == nil || hourlyRate! <= 0) {
            errorMessage = "Hourly rate is missing."
            return
        }

        guard breaks.allSatisfy({ $0.start >= work.start && $0.end <= work.end && $0.end > $0.start }) else {
            errorMessage = "Break times must be within the shift."
            return
        }
        let session: WorkSession
        if let existing = editingSession {
            session = existing
            session.workplaceID = workplaceID
            session.startAt = start
            session.endAt = end
            session.status = status
            session.hourlyRateSnapshot = hourlyRate
            session.fixedDailyPaySnapshot = fixed
            session.nightPremiumSnapshot = session.nightPremiumSnapshot ?? settings.nightPremiumEnabled
            session.overtimePremiumSnapshot = session.overtimePremiumSnapshot ?? settings.overtimePremiumEnabled
            for item in storedBreaks where item.sessionID == session.id {
                context.delete(item)
            }
        } else {
            session = WorkSession(
                workplaceID: workplaceID, startAt: start, endAt: end, status: status,
                payMode: selectedMode, hourlyRateSnapshot: hourlyRate,
                fixedDailyPaySnapshot: fixed
            )
            session.nightPremiumSnapshot = settings.nightPremiumEnabled
            session.overtimePremiumSnapshot = settings.overtimePremiumEnabled
            context.insert(session)
        }
        for rest in breaks {
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
