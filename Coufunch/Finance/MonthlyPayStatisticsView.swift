import SwiftUI
import SwiftData

struct MonthlyPayStatisticsView: View {
    private enum PayMode: String, CaseIterable {
        case gross = "세전"
        case net = "세후"
    }

    private struct MonthAmount: Identifiable {
        let month: Date
        let index: Int
        let completedDays: Int
        let gross: Decimal
        let net: Decimal

        var id: Date { month }
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

    @State private var mode: PayMode = .gross
    @State private var visibleMode: PayMode = .gross
    private enum BarPhase { case idle, descending, ascending }
    @State private var barPhase: BarPhase = .idle
    @State private var isTransitioning = false
    private let phaseDuration = 0.3
    @State private var selectedMonthIndex: Int?
    @State private var transitionTask: Task<Void, Never>?

    private var calendar: Calendar { .current }

    private var months: [MonthAmount] {
        let start = calendar.dateInterval(of: .month, for: .now)!.start
        return (0..<12).compactMap { index -> MonthAmount? in
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
            let net = EstimatedTakeHomeCalculator.calculate(
                gross: summary.total, shifts: []
            ).net
            return MonthAmount(
                month: month,
                index: index,
                completedDays: summary.completedDays,
                gross: summary.total,
                net: net
            )
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
        guard fixedYAxisMaximum > 0 else { return 0 }
        return phaseDuration * item.amount(for: visibleMode) / fixedYAxisMaximum
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

                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(months) { item in
                                Button {
                                    selectedMonthIndex = item.index
                                } label: {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(selected?.index == item.index
                                              ? CoufunchColor.primary
                                              : CoufunchColor.primary.opacity(0.55))
                                        .frame(
                                            maxWidth: .infinity,
                                            minHeight: 0
                                        )
                                        .frame(
                                            height: geometry.size.height *
                                                barValue(for: item) / fixedYAxisMaximum
                                        )
                                        .frame(maxHeight: .infinity, alignment: .bottom)
                                        .contentShape(Rectangle())
                                        .animation(
                                            .linear(duration: barDuration(for: item)),
                                            value: barPhase
                                        )
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel(
                                    "\(item.month.formatted(.dateTime.year().month())): \(formatted(visibleMode == .gross ? item.gross : item.net))"
                                )
                            }
                        }
                    }
                }
                .frame(height: chartHeight)

                HStack(spacing: 3) {
                    ForEach(months) { item in
                        Text(item.index.isMultiple(of: 2)
                             ? item.month.formatted(.dateTime.month(.twoDigits))
                             : "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 20)
            }
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

                monthlyBarChart

                Text("막대를 누르면 해당 월의 근무 정보가 표시됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let selected {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(selected.month.formatted(.dateTime.year().month(.wide)))
                            .font(.headline)
                        LabeledContent("완료 근무일", value: "\(selected.completedDays)일")
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
            let year = calendar.component(.year, from: .now)
            await holidays.load(year: year - 1)
            await holidays.load(year: year)
        }
        .onDisappear {
            transitionTask?.cancel()
            isTransitioning = false
            barPhase = .idle
        }
    }

}
