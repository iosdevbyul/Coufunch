import SwiftUI
import WakTrainerDesignSystem

/// Horizontal scrolling is performed on the common time ruler. Both lanes share
/// the same scroll offset; drag handles change endpoints in five-minute increments.
struct WorkTimelineEditor: View {
    @Binding var work: TimelineRange
    @Binding var breaks: [TimelineRange]

    @State private var handleAnchor: TimelineRange?
    @State private var activeBreakIndex = 0

    private let pointsPerHour: CGFloat = 132
    private var pointsPerMinute: CGFloat { pointsPerHour / 60 }
    private var contentWidth: CGFloat { CGFloat(TimelineSelection.maximumMinute) * pointsPerMinute }

    var body: some View {
        VStack(alignment: .leading, spacing: WakSpacing.medium) {
            Text("Work Hours")
                .font(WakTypography.screenTitle)
                .foregroundStyle(CoufunchColor.textPrimary)

            Text("Swipe to explore the timeline. Drag a colored handle, or use the five-minute adjustment buttons below.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 14) {
                    ruler
                    lane(title: "Shift", range: work, tint: CoufunchColor.primary, isBreak: false)
                    lane(title: "Break", range: breaks.indices.contains(activeBreakIndex) ? breaks[activeBreakIndex] : nil, tint: .orange, isBreak: true)
                }
                .frame(width: contentWidth)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.visible)

            VStack(alignment: .leading, spacing: WakSpacing.medium) {
                Label("Shift: \(label(work.start)) – \(label(work.end))", systemImage: "clock")
                    .font(.footnote.monospacedDigit())
                timeAdjustment(title: "Start", range: work, isBreak: false, edge: .start)
                timeAdjustment(title: "End", range: work, isBreak: false, edge: .end)
            }

            ForEach(breaks.indices, id: \.self) { index in
                HStack {
                    Button {
                        activeBreakIndex = index
                    } label: {
                        Text("Break \(index + 1): \(label(breaks[index].start)) – \(label(breaks[index].end))")
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

    private var ruler: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.clear).frame(width: contentWidth, height: 44)
            ForEach(0...48, id: \.self) { hour in
                let position = CGFloat(hour) * pointsPerHour
                VStack(alignment: .leading, spacing: 3) {
                    Text(hour < 24 ? String(format: "%02d:00", hour) : "+1d " + String(format: "%02d:00", hour - 24))
                        .font(.caption2.monospacedDigit())
                    Rectangle().fill(.secondary).frame(width: 1, height: 10)
                }
                .offset(x: position)
            }
            ForEach(0..<576, id: \.self) { tick in
                Rectangle()
                    .fill(CoufunchColor.textPrimary.opacity(0.14))
                    .frame(width: 1, height: tick.isMultiple(of: 12) ? 10 : 4)
                    .offset(x: CGFloat(tick * 5) * pointsPerMinute, y: 34)
            }
        }
        .accessibilityLabel("Timeline ruler, 48 hours in five-minute increments")
    }

    private func lane(title: String, range: TimelineRange?, tint: Color, isBreak: Bool) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(CoufunchColor.textPrimary.opacity(0.08))
                .frame(width: contentWidth, height: 54)

            if let range {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.6))
                    .frame(width: CGFloat(range.duration) * pointsPerMinute, height: 36)
                    .offset(x: CGFloat(range.start) * pointsPerMinute)
                    .accessibilityLabel("\(title) from \(label(range.start)) to \(label(range.end))")

                handle(edge: .start, range: range, tint: tint, isBreak: isBreak)
                handle(edge: .end, range: range, tint: tint, isBreak: isBreak)
            }
        }
        .frame(width: contentWidth, height: 54)
        .contentShape(Rectangle())

    }

    private func handle(edge: TimelineSelection.Edge, range: TimelineRange, tint: Color, isBreak: Bool) -> some View {
        RoundedRectangle(cornerRadius: 9)
            .fill(tint)
            .frame(width: 22, height: 48)
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(CoufunchColor.textPrimary, lineWidth: 1))
            .offset(x: CGFloat(edge == .start ? range.start : range.end) * pointsPerMinute - 11)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if handleAnchor == nil { handleAnchor = range }
                        guard let anchor = handleAnchor else { return }
                        let original = edge == .start ? anchor.start : anchor.end
                        let next = original + Int((value.translation.width / pointsPerMinute).rounded())
                        let bounds = isBreak ? work : TimelineRange(start: 0, end: TimelineSelection.maximumMinute)
                        if isBreak, breaks.indices.contains(activeBreakIndex) {
                            let updated = TimelineSelection.adjust(anchor, edge: edge, to: next, bounds: bounds)
                            guard !breaks.enumerated().contains(where: {
                                $0.offset != activeBreakIndex &&
                                updated.start < $0.element.end && $0.element.start < updated.end
                            }) else { return }
                            breaks[activeBreakIndex] = updated
                        } else if !isBreak {
                            work = TimelineSelection.adjust(anchor, edge: edge, to: next, bounds: bounds)
                        }
                    }
                    .onEnded { _ in handleAnchor = nil }
            )
            .accessibilityLabel(LocalizedStringKey(isBreak ? "Adjust break boundary" : "Adjust shift boundary"))
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
            .accessibilityLabel("Move \(title) five minutes earlier")
            Text(label(edge == .start ? range.start : range.end))
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 88)
            Button {
                adjustByStep(range: range, isBreak: isBreak, edge: edge, direction: 1)
            } label: {
                Image(systemName: "plus.circle")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Move \(title) five minutes later")
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
