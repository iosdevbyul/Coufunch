import SwiftUI
import SwiftData
import Charts

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
    @State private var displayedBarValues: [Double] = []
    @State private var isTransitioning = false
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

    private func changeMode(_ newMode: PayMode) {
        guard mode != newMode, !isTransitioning else { return }
        mode = newMode
        isTransitioning = true
        transitionTask?.cancel()

        // First animation: EVERY bar descends to the baseline together.
        withAnimation(.easeInOut(duration: 0.35)) {
            displayedBarValues = Array(repeating: 0, count: months.count)
        }

        transitionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }

            // Replace the data only after every rendered bar has reached zero.
            visibleMode = newMode
            let nextValues = months.map { $0.amount(for: newMode) }

            // Second animation: EVERY bar grows from the baseline together.
            withAnimation(.easeInOut(duration: 0.55)) {
                displayedBarValues = nextValues
            }
            try? await Task.sleep(for: .milliseconds(570))
            guard !Task.isCancelled else { return }
            isTransitioning = false
        }
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

                Chart(months) { item in
                    BarMark(
                        x: .value("월", item.index),
                        y: .value("급여", displayedBarValues.indices.contains(item.index) ? displayedBarValues[item.index] : item.amount(for: visibleMode))
                    )
                    .foregroundStyle(
                        selected?.index == item.index
                        ? CoufunchColor.primary : CoufunchColor.primary.opacity(0.55)
                    )
                    .cornerRadius(5)
                }
                .chartXScale(domain: -0.6...11.6)
                .chartYScale(domain: 0...fixedYAxisMaximum)
                .chartXAxis {
                    AxisMarks(values: [0, 2, 4, 6, 8, 10]) { axis in
                        AxisValueLabel {
                            if let index = axis.as(Int.self),
                               let item = months.first(where: { $0.index == index }) {
                                Text(item.month.formatted(.dateTime.month(.twoDigits)))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { axis in
                        AxisGridLine()
                        AxisValueLabel {
                            if let value = axis.as(Double.self) {
                                Text(value.formatted(.number.notation(.compactName)))
                            }
                        }
                    }
                }
                .chartXSelection(value: $selectedMonthIndex)
                .frame(height: 260)
                .frame(maxWidth: .infinity)

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
        .onAppear {
            displayedBarValues = months.map { $0.amount(for: visibleMode) }
        }
        .onDisappear {
            transitionTask?.cancel()
            isTransitioning = false
        }
    }

}
