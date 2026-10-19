import SwiftUI
import WakTrainerDesignSystem

/// Horizontal scrolling is performed on the common time ruler. Both lanes share
/// the same scroll offset; drag handles change endpoints in five-minute increments.
struct WorkTimelineEditor: View {
    @Binding var work: TimelineRange
    @Binding var breaks: [TimelineRange]

    @State private var dragAnchor: Int?
    @State private var selectingBreak = false
    @State private var handleAnchor: TimelineRange?
    @State private var activeBreakIndex = 0

    private let pointsPerHour: CGFloat = 132
    private var pointsPerMinute: CGFloat { pointsPerHour / 60 }
    private var contentWidth: CGFloat { CGFloat(TimelineSelection.maximumMinute) * pointsPerMinute }

    var body: some View {
        VStack(alignment: .leading, spacing: WakSpacing.medium) {
            Text("Work Hours")
                .font(WakTypography.screenTitle)
                .foregroundStyle(WakColor.textPrimary)

            Text("Scroll horizontally on the ruler. Drag across an empty lane to select a range; drag the handles for five-minute adjustments.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 14) {
                    ruler
                    lane(title: "Shift", range: work, tint: WakColor.primary, isBreak: false)
                    lane(title: "Break", range: breaks.indices.contains(activeBreakIndex) ? breaks[activeBreakIndex] : nil, tint: .orange, isBreak: true)
                }
                .frame(width: contentWidth)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.visible)

            HStack {
                Label("Shift: \(label(work.start)) – \(label(work.end))", systemImage: "clock")
                Spacer()
            }
            .font(.footnote)

            ForEach(breaks.indices, id: \.self) { index in
                HStack {
                    Button {
                        activeBreakIndex = index
                    } label: {
                        Text("Break \(index + 1): \(label(breaks[index].start)) – \(label(breaks[index].end))")
                    }
                    .foregroundStyle(activeBreakIndex == index ? WakColor.primary : WakColor.textPrimary)
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

            Button("Add Break") {
                let occupied = breaks.sorted { $0.start < $1.start }
                var cursor = work.start
                for rest in occupied {
                    if rest.start - cursor >= 5 { break }
                    cursor = max(cursor, rest.end)
                }
                if work.end - cursor >= 5 {
                    breaks.append(TimelineRange(start: cursor, end: min(cursor + 60, work.end)))
                    activeBreakIndex = breaks.count - 1
                }
            }
            .disabled(work.duration < TimelineSelection.step)

            Text("Work is attributed to its start date, including overnight shifts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(WakSpacing.large)
        .background(WakColor.background)
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
                    .fill(WakColor.textPrimary.opacity(0.14))
                    .frame(width: 1, height: tick.isMultiple(of: 12) ? 10 : 4)
                    .offset(x: CGFloat(tick * 5) * pointsPerMinute, y: 34)
            }
        }
        .accessibilityLabel("Timeline ruler, 48 hours in five-minute increments")
    }

    private func lane(title: String, range: TimelineRange?, tint: Color, isBreak: Bool) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(WakColor.textPrimary.opacity(0.08))
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
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    // Only start a new selection when the user begins in empty space.
                    let originMinute = TimelineSelection.snap(Double(value.startLocation.x / pointsPerMinute))
                    if dragAnchor == nil {
                        if let range, originMinute >= range.start && originMinute <= range.end {
                            return
                        }
                        dragAnchor = originMinute
                        selectingBreak = isBreak
                    }
                    guard selectingBreak == isBreak, let anchor = dragAnchor else { return }
                    let current = TimelineSelection.snap(Double(value.location.x / pointsPerMinute))
                    var selection = TimelineSelection.selection(from: anchor, to: current)
                    if isBreak {
                        guard let contained = TimelineSelection.contained(selection, within: work) else { return }
                        selection = contained
                        if breaks.indices.contains(activeBreakIndex) { breaks[activeBreakIndex] = selection }
                    } else {
                        work = selection
                    }
                }
                .onEnded { _ in
                    dragAnchor = nil
                }
        )
    }

    private func handle(edge: TimelineSelection.Edge, range: TimelineRange, tint: Color, isBreak: Bool) -> some View {
        RoundedRectangle(cornerRadius: 9)
            .fill(tint)
            .frame(width: 22, height: 48)
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(WakColor.textPrimary, lineWidth: 1))
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
                            breaks[activeBreakIndex] = TimelineSelection.adjust(anchor, edge: edge, to: next, bounds: bounds)
                        } else if !isBreak {
                            work = TimelineSelection.adjust(anchor, edge: edge, to: next, bounds: bounds)
                        }
                    }
                    .onEnded { _ in handleAnchor = nil }
            )
            .accessibilityLabel(isBreak ? "Adjust break boundary" : "Adjust shift boundary")
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
