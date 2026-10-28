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
    @State private var work = TimelineRange(start: 540, end: 1080)
    @State private var breaks = [TimelineRange(start: 720, end: 780)]
    @State private var overrideAmount = ""
    @State private var earlyDeparture = false
    @State private var scheduledEndMinute = 1080
    @State private var errorMessage: String?

    private var currentSettings: WorkplacePaySettings? {
        settings.first { $0.workplaceID == workplaceID }
    }

    private var holidayMinutes: Int {
        guard let midnight = Calendar.current.dateInterval(of: .day, for: date)?.start else { return 0 }
        let draft = WorkSession(workplaceID: workplaceID ?? UUID(),
            startAt: midnight.addingTimeInterval(Double(work.start * 60)),
            endAt: midnight.addingTimeInterval(Double(work.end * 60)))
        let rests = breaks.map {
            WorkBreak(sessionID: draft.id,
                startAt: midnight.addingTimeInterval(Double($0.start * 60)),
                endAt: midnight.addingTimeInterval(Double($0.end * 60)))
        }
        return HolidayWorkMinutes.calculate(session: draft, breaks: rests,
            holidayDates: holidayStore.dates)
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
                                fixedDailyPaySnapshot: fixedPay,
                                scheduledEndAt: earlyDeparture ? midnight.addingTimeInterval(Double(scheduledEndMinute * 60)) : nil)
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

    private func timeLabel(_ minute: Int) -> String {
        String(format: "%02d:%02d", (minute / 60) % 24, minute % 60)
            + (minute >= 1440 ? " (+\(minute / 1440)d)" : "")
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

                    Toggle("Left Early", isOn: $earlyDeparture)
                        .onChange(of: earlyDeparture) { _, enabled in
                            if enabled {
                                scheduledEndMinute = max(scheduledEndMinute, work.end + 1)
                            } else {
                                work.end = scheduledEndMinute
                            }
                        }
                    if earlyDeparture {
                        Text(String(format: String(localized: "Scheduled end: %@"), timeLabel(scheduledEndMinute)))
                        Stepper(String(format: String(localized: "Actual end: %@"), timeLabel(work.end)), value: $work.end,
                                in: (work.start + 1)...max(work.start + 1, scheduledEndMinute - 1),
                                step: 1)
                        Text("Early-departure incentives will be evaluated once workplace rules are defined.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    WorkTimelineEditor(work: $work, breaks: $breaks)

                    if (editingSession?.payMode ?? currentSettings?.payMode) == .fixedDaily {
                        TextField("Daily pay override (optional)", text: $overrideAmount)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    }

                    if let preview = payPreview {
                        CoufunchCard {
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
                                    .foregroundStyle(CoufunchColor.primary)
                                Text("Before deductions. Overtime estimates assume eligible employment and daily work exceeding 8 paid hours; weekly and holiday rules are not included.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let holidayError = holidayStore.errorMessage {
                        Text(LocalizedStringKey(holidayError)).font(.caption).foregroundStyle(.orange)
                    }
                    if let errorMessage {
                        Text(LocalizedStringKey(errorMessage)).foregroundStyle(.red).font(.footnote)
                    }
                    Button("Save Work Session") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(workplaceID == nil)
                }
                .padding(WakSpacing.medium)
            }
            .background(CoufunchColor.background)
            .navigationTitle(editingSession == nil ? "Add Work Session" : "Edit Work Session")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(workplaceID == nil)
                        .accessibilityLabel("Save Work Session")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onSaved)
                        .foregroundStyle(.red)
                }
            }
        }
        .tint(CoufunchColor.primary)
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
        scheduledEndMinute = endMinute
        if let planned = session.scheduledEndAt {
            earlyDeparture = true
            scheduledEndMinute = Int(planned.timeIntervalSince(startOfDay) / 60)
        }
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
              work.end > work.start,
              !earlyDeparture || (scheduledEndMinute > work.end && scheduledEndMinute <= TimelineSelection.maximumMinute) else {
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
            session.scheduledEndAt = earlyDeparture
                ? midnight.addingTimeInterval(TimeInterval(scheduledEndMinute * 60)) : nil
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
                fixedDailyPaySnapshot: fixed,
                scheduledEndAt: earlyDeparture
                    ? midnight.addingTimeInterval(TimeInterval(scheduledEndMinute * 60)) : nil
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
