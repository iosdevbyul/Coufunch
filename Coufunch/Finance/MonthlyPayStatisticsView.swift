import SwiftUI
import SwiftData

/// Animatable drawing without changing the layout of the chart columns.
private struct PayrollBarShape: Shape {
    var heightFraction: CGFloat

    var animatableData: CGFloat {
        get { heightFraction }
        set { heightFraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let height = rect.height * min(1, max(0, heightFraction))
        guard height > 0 else { return Path() }
        return Path(roundedRect: CGRect(
            x: rect.minX, y: rect.maxY - height,
            width: rect.width, height: height
        ), cornerRadius: 3)
    }
}

/// Lightweight line overlay that leaves the existing fixed-layout bars untouched.
private struct AveragePayLine: Shape {
    let values: [CGFloat?]
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !values.isEmpty else { return path }
        let slotWidth = rect.width / CGFloat(values.count)
        var previousWasValid = false
        for (index, ratio) in values.enumerated() {
            guard let ratio else {
                previousWasValid = false
                continue
            }
            let point = CGPoint(
                x: rect.minX + slotWidth * (CGFloat(index) + 0.5),
                y: rect.maxY - rect.height * max(0, min(1, ratio)) * progress
            )
            if previousWasValid { path.addLine(to: point) }
            else { path.move(to: point) }
            previousWasValid = true
        }
        return path
    }
}

struct MonthlyPayStatisticsView: View {
    private enum PayMode: String, CaseIterable {
        case gross = "세전"
        case net = "세후"
    }

    private struct MonthAmount: Identifiable {
        let month: Date
        let index: Int
        let completedDays: Int
        let completedShifts: Int
        let gross: Decimal
        let net: Decimal

        var id: Date { month }
        func average(for mode: PayMode) -> Decimal? {
            guard completedShifts > 0 else { return nil }
            let amount = mode == .gross ? gross : net
            return Decimal(NSDecimalNumber(decimal: amount).int64Value / Int64(completedShifts))
        }
        func amount(for mode: PayMode) -> Double {
            NSDecimalNumber(decimal: mode == .gross ? gross : net).doubleValue
        }
    }

    @Query private var sessions: [WorkSession]
    @Query private var breaks: [WorkBreak]
    @Query private var workplaces: [Workplace]
    @Query private var settings: [WorkplacePaySettings]
    @Query private var rules: [IncentiveRule]
    @Query private var manual: [ManualIncentive]
    @StateObject private var holidays = KoreanPublicHolidayStore()

    @State private var cachedMonths: [MonthAmount] = []
    @State private var mode: PayMode = .gross
    @State private var visibleMode: PayMode = .gross
    private enum BarPhase { case idle, descending, ascending }
    @State private var barPhase: BarPhase = .idle
    @State private var isTransitioning = false
    private let phaseDuration = 0.3
    @State private var selectedMonthIndex: Int?
    @State private var transitionTask: Task<Void, Never>?

    private var calendar: Calendar { .current }

    private var months: [MonthAmount] { cachedMonths }

    private func rebuildMonthSnapshot() {
        let start = calendar.dateInterval(of: .month, for: .now)!.start
        cachedMonths = (0..<12).compactMap { index -> MonthAmount? in
            let offset = 11 - index
            guard let month = calendar.date(byAdding: .month, value: -offset, to: start) else {
                return nil
            }
            let summary = WorkFinanceSummary.summarize(
                month: month,
                sessions: sessions,
                breaks: breaks,
                workplaces: workplaces,
                settings: settings,
                rules: rules,
                manual: manual,
                calendar: calendar,
                holidayDates: holidays.dates
            )
            // A month without completed shifts must not show an unexplained pay bar.
            // Incentive-only amounts remain in the payroll ledger, but are not treated
            // as worked-month earnings in this attendance-based statistics view.
            let gross = summary.completedDays > 0 ? summary.total : Decimal.zero
            let net = EstimatedTakeHomeCalculator.calculate(
                gross: gross, shifts: []
            ).net
            let interval = calendar.dateInterval(of: .month, for: month)!
            let completedShifts = sessions.filter { $0.status == .completed && interval.contains($0.startAt) }.count
            return MonthAmount(
                month: month,
                index: index,
                completedDays: summary.completedDays,
                completedShifts: completedShifts,
                gross: gross,
                net: net
            )
        }
    }

    private var fixedAverageMaximum: Double {
        max(1, months.flatMap { [ $0.average(for: .gross), $0.average(for: .net) ] }
            .compactMap { $0.map { NSDecimalNumber(decimal: $0).doubleValue } }
            .max() ?? 0) * 1.12
    }

    private var averageLineRatios: [CGFloat?] {
        months.map { month in
            guard let average = month.average(for: visibleMode) else { return nil }
            return CGFloat(NSDecimalNumber(decimal: average).doubleValue / fixedAverageMaximum)
        }
    }

    private var selected: MonthAmount? {
        guard let selectedMonthIndex else { return months.last }
        return months.first { $0.index == selectedMonthIndex }
    }

    // Fixed for both modes so axis labels and grid lines never move during a toggle.
    private var fixedYAxisMaximum: Double {
        max(1, months.map { max($0.amount(for: .gross), $0.amount(for: .net)) }.max() ?? 0) * 1.12
    }

    private func formatted(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: "KRW").precision(.fractionLength(0)))
    }

    // The tallest bar takes 0.3 seconds. Other bars use the same value-per-second
    // speed and therefore reach zero (or their target) earlier.
    private func barDuration(for item: MonthAmount) -> Double {
        let tallestBar = months.map { $0.amount(for: visibleMode) }.max() ?? 0
        guard tallestBar > 0 else { return 0 }
        return phaseDuration * item.amount(for: visibleMode) / tallestBar
    }

    private func barValue(for item: MonthAmount) -> Double {
        barPhase == .descending ? 0 : item.amount(for: visibleMode)
    }

    private func changeMode(_ newMode: PayMode) {
        guard mode != newMode, !isTransitioning else { return }
        transitionTask?.cancel()
        mode = newMode
        isTransitioning = true
        barPhase = .descending

        transitionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(phaseDuration))
            guard !Task.isCancelled else { return }

            // All bars are at zero before any new bar starts rising.
            visibleMode = newMode
            barPhase = .ascending

            try? await Task.sleep(for: .seconds(phaseDuration))
            guard !Task.isCancelled else { return }
            barPhase = .idle
            isTransitioning = false
        }
    }

    // Static axis and grid layout; only the individual rectangles are animated.
    private var monthlyBarChart: some View {
        let chartHeight: CGFloat = 220

        return HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .trailing) {
                Text(fixedYAxisMaximum.formatted(.number.notation(.compactName)))
                Spacer()
                Text((fixedYAxisMaximum / 2).formatted(.number.notation(.compactName)))
                Spacer()
                Text("0")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(width: 48, height: chartHeight)

            VStack(spacing: 5) {
                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        VStack {
                            Rectangle().fill(.gray.opacity(0.25)).frame(height: 1)
                            Spacer()
                            Rectangle().fill(.gray.opacity(0.25)).frame(height: 1)
                            Spacer()
                            Rectangle().fill(.gray.opacity(0.35)).frame(height: 1)
                        }

                        HStack(alignment: .bottom, spacing: 2) {
                            ForEach(months) { item in
                                Button {
                                    selectedMonthIndex = item.index
                                } label: {
                                    PayrollBarShape(
                                        heightFraction: CGFloat(barValue(for: item) / fixedYAxisMaximum)
                                    )
                                    .fill(selected?.index == item.index
                                          ? CoufunchColor.primary
                                          : CoufunchColor.primary.opacity(0.55))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .animation(
                                        .linear(duration: barDuration(for: item)),
                                        value: barPhase
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel(
                                    "\(item.month.formatted(.dateTime.year().month())): \(formatted(visibleMode == .gross ? item.gross : item.net))"
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        // The right-hand series uses its own fixed scale.
                        // Missing-work months break the line rather than creating false zeros.
                        AveragePayLine(
                            values: averageLineRatios,
                            progress: barPhase == .descending ? 0 : 1
                        )
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .animation(.linear(duration: phaseDuration), value: barPhase)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                        HStack(spacing: 2) {
                            ForEach(months) { item in
                                GeometryReader { column in
                                    if let average = item.average(for: visibleMode), barPhase != .descending {
                                        Circle()
                                            .fill(Color.orange)
                                            .frame(width: 6, height: 6)
                                            .position(
                                                x: column.size.width / 2,
                                                y: column.size.height * (1 - CGFloat(
                                                    NSDecimalNumber(decimal: average).doubleValue / fixedAverageMaximum
                                                ))
                                            )
                                    }
                                }
                            }
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                    }
                }
                .frame(height: chartHeight)

                HStack(spacing: 2) {
                    ForEach(months) { item in
                        Text(item.index.isMultiple(of: 3)
                             ? item.month.formatted(.dateTime.month(.twoDigits))
                             : "")
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 20)
            }

            VStack(alignment: .leading) {
                Text(fixedAverageMaximum.formatted(.number.notation(.compactName)))
                Spacer()
                Text((fixedAverageMaximum / 2).formatted(.number.notation(.compactName)))
                Spacer()
                Text("0")
            }
            .font(.caption2)
            .foregroundStyle(.orange)
            .frame(width: 48, height: chartHeight)
        }
        .frame(maxWidth: .infinity)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("월별 급여 변화")
                    .font(.title2.bold())

                HStack(spacing: 0) {
                    ForEach(PayMode.allCases, id: \.self) { value in
                        Button {
                            changeMode(value)
                        } label: {
                            Text(value.rawValue)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .foregroundStyle(mode == value ? Color.white : Color.primary)
                                .background(
                                    mode == value ? CoufunchColor.primary : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isTransitioning)
                        .accessibilityAddTraits(mode == value ? .isSelected : [])
                    }
                }
                .padding(4)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))

                HStack(spacing: 16) {
                    Label("월 총급여", systemImage: "chart.bar.fill")
                        .foregroundStyle(CoufunchColor.primary)
                    Label("1회 평균 급여", systemImage: "waveform.path")
                        .foregroundStyle(.orange)
                }
                .font(.caption)

                monthlyBarChart

                Text("막대를 누르면 해당 월의 근무 정보가 표시됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let selected {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(selected.month.formatted(.dateTime.year().month(.wide)))
                            .font(.headline)
                        LabeledContent("완료 근무일", value: "\(selected.completedDays)일")
                        LabeledContent("완료 근무 횟수", value: "\(selected.completedShifts)회")
                        if let average = selected.average(for: mode) {
                            LabeledContent(mode == .gross ? "1회 평균 세전 급여" : "1회 평균 세후 예상 급여", value: formatted(average))
                            Text("월 급여 합계(수당·인센티브 포함) ÷ 완료 근무 횟수")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            LabeledContent("1회 평균 근무 급여", value: "근무 기록 없음")
                        }
                        LabeledContent("세전 급여", value: formatted(selected.gross))
                        LabeledContent("세후 예상 급여", value: formatted(selected.net))
                        Divider()
                        HStack {
                            Text(mode == .gross ? "선택한 세전 금액" : "선택한 세후 예상 금액")
                            Spacer()
                            Text(formatted(mode == .gross ? selected.gross : selected.net))
                                .fontWeight(.bold)
                                .foregroundStyle(CoufunchColor.primary)
                        }
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }

                Text("세후 금액은 현재 앱의 보험료 추정 계산을 사용합니다. 실제 입금액 및 세금과 다를 수 있습니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("통계")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Let navigation render before running the expensive monthly aggregation.
            await Task.yield()
            rebuildMonthSnapshot()
            let year = calendar.component(.year, from: .now)
            await holidays.load(year: year - 1)
            await holidays.load(year: year)
            rebuildMonthSnapshot()
        }
        .onDisappear {
            transitionTask?.cancel()
            isTransitioning = false
            barPhase = .idle
        }
    }

}
