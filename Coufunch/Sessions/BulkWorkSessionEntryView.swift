import SwiftUI
import SwiftData
import WakTrainerDesignSystem

/// Multi-date entry for shifts sharing one set of work conditions.
struct BulkWorkSessionEntryView: View {
    let initialMonth: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Workplace.name) private var workplaces: [Workplace]
    @Query private var settings: [WorkplacePaySettings]
    @Query private var existingSessions: [WorkSession]

    @State private var displayedMonth = Date()
    @State private var selectedDates: Set<Date> = []
    @State private var step = 0
    @State private var workplaceID: UUID?
    @State private var status: WorkSessionStatus = .completed
    @State private var work = TimelineRange(start: 540, end: 1080)
    @State private var breaks = [TimelineRange(start: 720, end: 780)]
    @State private var fixedAmount = ""
    @State private var errorMessage: String?
    @State private var showSaveConfirmation = false

    private var calendar: Calendar { .current }
    private var selectedSettings: WorkplacePaySettings? {
        settings.first { $0.workplaceID == workplaceID }
    }
    private var sortedDates: [Date] { selectedDates.sorted() }

    private var days: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth),
              let range = calendar.range(of: .day, in: .month, for: interval.start) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let padding = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: padding) + range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        }.map(Optional.some)
    }

    private struct Prepared {
        let date: Date
        let start: Date
        let end: Date
        let scheduledEnd: Date?
        let rate: Decimal?
        let fixed: Decimal?
    }

    private func prepared(_ date: Date) -> Prepared? {
        guard let settings = selectedSettings,
              let day = calendar.dateInterval(of: .day, for: date)?.start else { return nil }
        let start = day.addingTimeInterval(Double(work.start * 60))
        let end = day.addingTimeInterval(Double(work.end * 60))
        let rate: Decimal?
        let fixed: Decimal?
        switch settings.payMode {
        case .minimumHourly:
            rate = MinimumWageSchedule.hourlyRate(for: start)
            fixed = nil
        case .customHourly:
            rate = settings.customHourlyRate
            fixed = nil
        case .fixedDaily:
            rate = nil
            fixed = fixedAmount.isEmpty ? settings.fixedDailyPay : Decimal(string: fixedAmount)
        }
        return Prepared(date: date, start: start, end: end, scheduledEnd: nil, rate: rate, fixed: fixed)
    }

    private var preview: (new: [Prepared], skipped: Int) {
        guard let workplaceID else { return ([], 0) }
        let preparedDates = sortedDates.compactMap(prepared)
        let additions = preparedDates.filter { proposal in
            !existingSessions.contains {
                $0.workplaceID == workplaceID && abs($0.startAt.timeIntervalSince(proposal.start)) < 1
            }
        }
        return (additions, preparedDates.count - additions.count)
    }

    private var isValid: Bool {
        guard let settings = selectedSettings,
              work.start >= 0, work.end > work.start,
              work.end <= TimelineSelection.maximumMinute,
              breaks.allSatisfy({ $0.start >= work.start && $0.end <= work.end && $0.end > $0.start })
        else { return false }
        if settings.payMode == .fixedDaily {
            let amount = fixedAmount.isEmpty ? settings.fixedDailyPay : Decimal(string: fixedAmount)
            return amount.map { $0 >= 0 } ?? false
        }
        return sortedDates.allSatisfy {
            (prepared($0)?.rate).map { $0 > 0 } ?? false
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if step == 0 {
                        Text("근무한 날짜를 모두 선택하세요. 다시 누르면 선택이 해제됩니다.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                                .accessibilityLabel("이전 달")
                            Spacer()
                            Text(displayedMonth.formatted(.dateTime.year().month(.wide))).font(.headline)
                            Spacer()
                            Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                                .accessibilityLabel("다음 달")
                        }
                        .padding(.vertical, 8)
                        let symbols = calendar.veryShortStandaloneWeekdaySymbols
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                            ForEach(0..<7, id: \.self) { index in
                                Text(symbols[(index + calendar.firstWeekday - 1) % 7])
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(Array(days.enumerated()), id: \.offset) { entry in
                                if let date = entry.element {
                                    let active = selectedDates.contains(date)
                                    Button {
                                        if active { selectedDates.remove(date) }
                                        else { selectedDates.insert(date) }
                                    } label: {
                                        Text(date.formatted(.dateTime.day()))
                                            .font(.subheadline)
                                            .frame(maxWidth: .infinity, minHeight: 40)
                                            .foregroundStyle(active ? Color.white : Color.primary)
                                            .background(active ? CoufunchColor.primary : Color.clear,
                                                        in: RoundedRectangle(cornerRadius: 9))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(active ? .isSelected : [])
                                } else {
                                    Color.clear.frame(height: 40)
                                }
                            }
                        }
                        Text("선택한 날짜: \(selectedDates.count)일")
                            .font(.headline)
                        if !selectedDates.isEmpty {
                            Text(sortedDates.map { $0.formatted(.dateTime.month(.twoDigits).day(.twoDigits)) }.joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button("다음 · 공통 근무조건") { step = 1 }
                            .buttonStyle(.borderedProminent)
                            .disabled(selectedDates.isEmpty)
                    } else {
                        Text("\(selectedDates.count)개 날짜에 동일한 근무조건을 적용합니다.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Picker("근무지", selection: $workplaceID) {
                            Text("근무지 선택").tag(Optional<UUID>.none)
                            ForEach(workplaces) { workplace in
                                Text(workplace.name).tag(Optional(workplace.id))
                            }
                        }
                        .pickerStyle(.menu)
                        Picker("상태", selection: $status) {
                            Text("신청").tag(WorkSessionStatus.applied)
                            Text("확정").tag(WorkSessionStatus.confirmed)
                            Text("완료").tag(WorkSessionStatus.completed)
                        }
                        .pickerStyle(.segmented)
                        WorkTimelineEditor(work: $work, breaks: $breaks)
                        if selectedSettings?.payMode == .fixedDaily {
                            TextField("공통 일당 직접 입력 (선택)", text: $fixedAmount)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                        }
                        let counts = preview
                        VStack(alignment: .leading, spacing: 8) {
                            Text("저장 전 확인").font(.headline)
                            LabeledContent("선택 날짜", value: "\(sortedDates.count)개")
                            LabeledContent("새로 추가", value: "\(counts.new.count)건")
                            LabeledContent("기존 기록과 중복", value: "\(counts.skipped)건 (제외)")
                            Text("같은 근무지와 시작 시간이 이미 있으면 건너뜁니다. 기존 기록은 수정하지 않습니다.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        if let errorMessage {
                            Text(errorMessage).foregroundStyle(.red).font(.footnote)
                        }
                        HStack {
                            Button("날짜 다시 선택") { step = 0 }
                                .buttonStyle(.bordered)
                            Button("일괄 저장") { showSaveConfirmation = true }
                                .buttonStyle(.borderedProminent)
                                .disabled(!isValid || counts.new.isEmpty)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("여러 날짜 근무 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                        .foregroundStyle(.red)
                }
            }
            .confirmationDialog(
                "\(preview.new.count)건의 근무를 저장할까요?",
                isPresented: $showSaveConfirmation,
                titleVisibility: .visible
            ) {
                Button("\(preview.new.count)건 저장") { saveAll() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("중복 \(preview.skipped)건은 제외하고 저장합니다.")
            }
            .onAppear {
                displayedMonth = calendar.dateInterval(of: .month, for: initialMonth)?.start ?? initialMonth
                workplaceID = workplaceID ?? workplaces.first?.id
            }
        }
        .tint(CoufunchColor.primary)
    }

    private func moveMonth(_ offset: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) ?? displayedMonth
    }

    private func saveAll() {
        guard isValid, let workplaceID, let settings = selectedSettings else { return }
        let records = preview.new
        guard !records.isEmpty else { return }
        for record in records {
            let session = WorkSession(
                workplaceID: workplaceID,
                startAt: record.start,
                endAt: record.end,
                status: status,
                payMode: settings.payMode,
                hourlyRateSnapshot: record.rate,
                fixedDailyPaySnapshot: record.fixed,
                scheduledEndAt: record.scheduledEnd
            )
            session.nightPremiumSnapshot = settings.nightPremiumEnabled
            session.overtimePremiumSnapshot = settings.overtimePremiumEnabled
            context.insert(session)
            let day = calendar.dateInterval(of: .day, for: record.date)!.start
            for rest in breaks {
                context.insert(WorkBreak(
                    sessionID: session.id,
                    startAt: day.addingTimeInterval(Double(rest.start * 60)),
                    endAt: day.addingTimeInterval(Double(rest.end * 60))
                ))
            }
        }
        do {
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            errorMessage = "일괄 저장에 실패했습니다. 변경 사항을 다시 확인해 주세요."
        }
    }
}
