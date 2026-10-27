import SwiftUI
import WakTrainerDesignSystem

/// Horizontal scrolling is performed on the common time ruler. Both lanes share
/// the same scroll offset; drag handles change endpoints in five-minute increments.
struct WorkTimelineEditor: View {
    @Binding var work: TimelineRange
    @Binding var breaks: [TimelineRange]

    @State private var selectionAnchor: Int?
    @State private var activeBreakIndex = 0


    var body: some View {
        VStack(alignment: .leading, spacing: WakSpacing.medium) {
            Text("Work Hours")
                .font(WakTypography.screenTitle)
                .foregroundStyle(CoufunchColor.textPrimary)

            Text("근무시간 선택: 시작 시간부터 종료 시간까지 쭉 드래그하세요. 시간은 5분 단위로 선택됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("시작 시간부터 종료 시간까지 아래 시간표를 한 번에 그어 선택하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                GeometryReader { geometry in
                    let width = max(1, geometry.size.width)
                    let toX: (Int) -> CGFloat = {
                        width * CGFloat($0) / CGFloat(TimelineSelection.maximumMinute)
                    }
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(CoufunchColor.textPrimary.opacity(0.08))
                        ForEach(0...8, id: \.self) { tick in
                            let minute = tick * 360
                            VStack(spacing: 4) {
                                Text(tick < 4 ? "\(tick * 6)시" : "+1일 \((tick - 4) * 6)시")
                                    .font(.system(size: 9))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                Rectangle()
                                    .fill(.secondary.opacity(0.3))
                                    .frame(width: 1, height: 46)
                            }
                            .offset(x: min(width - 20, max(0, toX(minute) - 10)), y: 7)
                        }
                        RoundedRectangle(cornerRadius: 7)
                            .fill(CoufunchColor.primary.opacity(0.75))
                            .frame(width: max(2, toX(work.end - work.start)), height: 34)
                            .offset(x: toX(work.start), y: 41)
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                    .onChanged { value in
                                        if selectionAnchor == nil {
                                            selectionAnchor = minute(at: value.startLocation.x, width: width)
                                        }
                                        guard let anchor = selectionAnchor else { return }
                                        work = TimelineSelection.selection(
                                            from: anchor,
                                            to: minute(at: value.location.x, width: width)
                                        )
                                    }
                                    .onEnded { _ in selectionAnchor = nil }
                            )
                    }
                }
                .frame(height: 84)
                Text("전체 48시간을 표시합니다. 자정 이후는 +1일이며, 아래 ± 버튼으로 5분씩 정밀 조정할 수 있습니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: WakSpacing.medium) {
                Label(String(format: String(localized: "Shift: %@ – %@"), label(work.start), label(work.end)), systemImage: "clock")
                    .font(.footnote.monospacedDigit())
                timeAdjustment(title: "Start", range: work, isBreak: false, edge: .start)
                timeAdjustment(title: "End", range: work, isBreak: false, edge: .end)
            }

            ForEach(breaks.indices, id: \.self) { index in
                HStack {
                    Button {
                        activeBreakIndex = index
                    } label: {
                        Text(String(format: String(localized: "Break %d: %@ – %@"), index + 1, label(breaks[index].start), label(breaks[index].end)))
                    }
                    .foregroundStyle(activeBreakIndex == index ? CoufunchColor.primary : CoufunchColor.textPrimary)
                    Spacer()
                    Button(role: .destructive) {
                        breaks.remove(at: index)
                        activeBreakIndex = max(0, min(activeBreakIndex, breaks.count - 1))
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                .font(.footnote)
            }

            if breaks.indices.contains(activeBreakIndex) {
                timeAdjustment(title: "Break Start", range: breaks[activeBreakIndex], isBreak: true, edge: .start)
                timeAdjustment(title: "Break End", range: breaks[activeBreakIndex], isBreak: true, edge: .end)
            }
            Button("Add Break") {
                let occupied = breaks.sorted { $0.start < $1.start }
                var cursor = work.start
                var gap: TimelineRange?
                for rest in occupied {
                    if rest.start - cursor >= TimelineSelection.step {
                        gap = TimelineRange(start: cursor, end: rest.start)
                        break
                    }
                    cursor = max(cursor, rest.end)
                }
                if gap == nil && work.end - cursor >= TimelineSelection.step {
                    gap = TimelineRange(start: cursor, end: work.end)
                }
                guard let gap else { return }
                breaks.append(TimelineRange(start: gap.start, end: min(gap.start + 60, gap.end)))
                activeBreakIndex = breaks.count - 1
            }
            .disabled(!hasAvailableBreakGap)

            Text("Work is attributed to its start date, including overnight shifts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(WakSpacing.large)
        .background(CoufunchColor.background)
        .onChange(of: work) { _, updated in
            breaks = breaks.compactMap { TimelineSelection.contained($0, within: updated) }
            activeBreakIndex = max(0, min(activeBreakIndex, breaks.count - 1))
        }
    }

    private func minute(at x: CGFloat, width: CGFloat) -> Int {
        let fraction = Double(max(0, min(width, x)) / max(width, 1))
        return TimelineSelection.snap(fraction * Double(TimelineSelection.maximumMinute))
    }

    private var hasAvailableBreakGap: Bool {
        let occupied = breaks.sorted { $0.start < $1.start }
        var cursor = work.start
        for rest in occupied {
            if rest.start - cursor >= TimelineSelection.step { return true }
            cursor = max(cursor, rest.end)
        }
        return work.end - cursor >= TimelineSelection.step
    }

    private func timeAdjustment(title: String, range: TimelineRange,
                                isBreak: Bool, edge: TimelineSelection.Edge) -> some View {
        HStack {
            Text(LocalizedStringKey(title)).font(.subheadline)
            Spacer()
            Button {
                adjustByStep(range: range, isBreak: isBreak, edge: edge, direction: -1)
            } label: {
                Image(systemName: "minus.circle")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(String(format: String(localized: "Move %@ five minutes earlier"), String(localized: String.LocalizationValue(title))))
            Text(label(edge == .start ? range.start : range.end))
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 88)
            Button {
                adjustByStep(range: range, isBreak: isBreak, edge: edge, direction: 1)
            } label: {
                Image(systemName: "plus.circle")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(String(format: String(localized: "Move %@ five minutes later"), String(localized: String.LocalizationValue(title))))
        }
    }

    private func adjustByStep(range: TimelineRange, isBreak: Bool,
                              edge: TimelineSelection.Edge, direction: Int) {
        let current = edge == .start ? range.start : range.end
        let bounds = isBreak ? work : TimelineRange(start: 0, end: TimelineSelection.maximumMinute)
        let updated = TimelineSelection.adjust(
            range, edge: edge, to: current + direction * TimelineSelection.step, bounds: bounds
        )
        if isBreak {
            guard breaks.indices.contains(activeBreakIndex),
                  !breaks.enumerated().contains(where: {
                      $0.offset != activeBreakIndex &&
                      updated.start < $0.element.end && $0.element.start < updated.end
                  }) else { return }
            breaks[activeBreakIndex] = updated
        } else {
            work = updated
        }
    }

    private func label(_ minute: Int) -> String {
        let day = minute / 1440
        let hour = (minute % 1440) / 60
        let min = minute % 60
        return String(format: "%02d:%02d", hour, min) + (day > 0 ? " (+\(day)d)" : "")
    }
}

#Preview {
    @Previewable @State var work = TimelineRange(start: 1140, end: 1680)
    @Previewable @State var rests = [TimelineRange(start: 1320, end: 1380)]
    WorkTimelineEditor(work: $work, breaks: $rests)
        .preferredColorScheme(.dark)
}
