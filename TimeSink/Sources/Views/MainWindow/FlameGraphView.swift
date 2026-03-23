import AppKit
import SwiftUI

struct FlameGraphView: View {
    let records: [ActivityRecord]
    let dayStart: Date
    let dayEnd: Date
    let categories: [Category]
    let selectedRecordID: Int64?
    var onRecordTapped: ((ActivityRecord) -> Void)?

    @State private var zoomLevel: CGFloat = 1.0
    @State private var panOffset: CGFloat = 0.0
    @State private var hoveredRecord: ActivityRecord?
    @State private var hoverLocation: CGPoint = .zero
    @State private var isHovering = false
    @State private var dragStartOffset: CGFloat?

    private let graphHeight: CGFloat = 46
    private let axisHeight: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Activity Map")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if zoomLevel > 1.01 {
                    Text("\(zoomLevel, specifier: "%.1f")x")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Capsule())

                    Button("Reset") {
                        withAnimation(.snappy(duration: 0.2)) {
                            zoomLevel = 1.0
                            panOffset = 0.0
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            VStack(spacing: 0) {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.primary.opacity(0.05), Color.primary.opacity(0.025)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Canvas { context, size in
                            drawHourMarkers(in: &context, size: size)
                            drawSegments(in: &context, size: size)
                            drawNowMarker(in: &context, size: size)
                        }

                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)

                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                handleHover(phase, width: geometry.size.width)
                            }
                            .gesture(dragGesture(width: geometry.size.width))
                            .simultaneousGesture(
                                MagnifyGesture()
                                    .onChanged { value in
                                        zoomLevel = min(max(1.0, value.magnification), 20.0)
                                        panOffset = clampPanOffset(panOffset)
                                    }
                            )
                            .onTapGesture { location in
                                guard let record = record(at: location.x, width: geometry.size.width) else { return }
                                onRecordTapped?(record)
                            }

                        CommandScrollCaptureView { event, pointInView in
                            guard event.modifierFlags.contains(.command) else { return false }

                            let anchor = max(0, min(1, pointInView.x / max(geometry.size.width, 1)))
                            zoomWithScroll(deltaY: event.scrollingDeltaY, anchorRatio: anchor)
                            return true
                        }
                        .allowsHitTesting(false)

                        if let hoveredRecord, isHovering {
                            FlameGraphTooltip(
                                record: hoveredRecord,
                                category: categories.first { $0.id == hoveredRecord.categoryId }
                            )
                            .offset(x: tooltipX(in: geometry.size.width), y: 8)
                            .allowsHitTesting(false)
                        }
                    }
                }
                .frame(height: graphHeight)

                GeometryReader { _ in
                    Canvas { context, size in
                        drawAxis(in: &context, size: size)
                    }
                }
                .frame(height: axisHeight)
            }

            if !legendEntries.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(legendEntries, id: \.appName) { entry in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(entry.color)
                                    .frame(width: 7, height: 7)
                                Text(entry.appName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var legendEntries: [(appName: String, color: Color)] {
        Array(AppColorHelper.legendEntries(for: records).prefix(8))
    }

    private var visibleDuration: TimeInterval {
        max(dayEnd.timeIntervalSince(dayStart), 1) / zoomLevel
    }

    private var visibleStart: Date {
        let total = max(dayEnd.timeIntervalSince(dayStart), 1)
        let hidden = max(total - visibleDuration, 0)
        return dayStart.addingTimeInterval(hidden * Double(panOffset))
    }

    private var visibleEnd: Date {
        visibleStart.addingTimeInterval(visibleDuration)
    }

    private func drawSegments(in context: inout GraphicsContext, size: CGSize) {
        for record in records {
            guard let rect = rect(for: record, width: size.width) else { continue }

            let baseColor = AppColorHelper.color(for: record.appName, isIdle: record.isIdle)
            let path = Path(roundedRect: rect, cornerRadius: min(6, rect.width / 2))
            context.fill(path, with: .color(baseColor.opacity(record.isIdle ? 0.45 : 0.96)))

            if selectedRecordID == record.id {
                context.stroke(path, with: .color(.white.opacity(0.95)), lineWidth: 2)
            }

            if rect.width > 54 {
                context.draw(
                    Text(record.isIdle ? "Idle" : record.appName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white),
                    at: CGPoint(x: rect.minX + 7, y: rect.midY),
                    anchor: .leading
                )
            }
        }
    }

    private func drawHourMarkers(in context: inout GraphicsContext, size: CGSize) {
        for hour in hourMarks() {
            let x = xPosition(for: hour, width: size.width)
            guard x >= 0, x <= size.width else { continue }
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(Color.primary.opacity(0.08)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }
    }

    private func drawAxis(in context: inout GraphicsContext, size: CGSize) {
        for hour in hourMarks() {
            let x = xPosition(for: hour, width: size.width)
            guard x >= 0, x <= size.width else { continue }
            context.draw(
                Text(DateFormatting.formatHour(Calendar.current.component(.hour, from: hour)))
                    .font(.caption2)
                    .foregroundColor(.secondary),
                at: CGPoint(x: max(22, min(size.width - 22, x)), y: axisHeight / 2),
                anchor: .center
            )
        }
    }

    private func drawNowMarker(in context: inout GraphicsContext, size: CGSize) {
        let now = Date()
        guard now >= dayStart, now <= dayEnd else { return }
        let x = xPosition(for: now, width: size.width)
        guard x >= 0, x <= size.width else { return }

        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(path, with: .color(.red.opacity(0.95)), lineWidth: 1.5)
        context.draw(
            Text("Now")
                .font(.caption2)
                .foregroundColor(.red),
            at: CGPoint(x: min(size.width - 18, max(18, x + 12)), y: 10),
            anchor: .leading
        )
    }

    private func rect(for record: ActivityRecord, width: CGFloat) -> CGRect? {
        let start = max(record.startedAt, visibleStart)
        let end = min(record.endedAt ?? Date(), visibleEnd)
        guard end > start else { return nil }

        let x1 = xPosition(for: start, width: width)
        let x2 = xPosition(for: end, width: width)
        return CGRect(x: x1, y: 6, width: max(1, x2 - x1), height: graphHeight - 12)
    }

    private func xPosition(for date: Date, width: CGFloat) -> CGFloat {
        let visibleRange = max(visibleEnd.timeIntervalSince(visibleStart), 1)
        let elapsed = date.timeIntervalSince(visibleStart)
        return CGFloat(elapsed / visibleRange) * width
    }

    private func hourMarks() -> [Date] {
        var marks: [Date] = []
        let calendar = Calendar.current
        var current = calendar.date(
            bySettingHour: calendar.component(.hour, from: visibleStart),
            minute: 0,
            second: 0,
            of: visibleStart
        ) ?? visibleStart
        if current < visibleStart {
            current = calendar.date(byAdding: .hour, value: 1, to: current) ?? current
        }
        while current <= visibleEnd {
            marks.append(current)
            current = calendar.date(byAdding: .hour, value: 1, to: current) ?? current
        }
        return marks
    }

    private func handleHover(_ phase: HoverPhase, width: CGFloat) {
        switch phase {
        case .active(let location):
            hoverLocation = location
            hoveredRecord = record(at: location.x, width: width)
            isHovering = hoveredRecord != nil
        case .ended:
            isHovering = false
            hoveredRecord = nil
        }
    }

    private func record(at x: CGFloat, width: CGFloat) -> ActivityRecord? {
        let visibleRange = max(visibleEnd.timeIntervalSince(visibleStart), 1)
        let ratio = max(0, min(1, x / max(width, 1)))
        let targetDate = visibleStart.addingTimeInterval(visibleRange * ratio)
        return records.first { record in
            let end = record.endedAt ?? Date()
            return record.startedAt <= targetDate && end >= targetDate
        }
    }

    private func tooltipX(in width: CGFloat) -> CGFloat {
        min(max(hoverLocation.x + 10, 0), max(0, width - 250))
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard zoomLevel > 1.01 else { return }
                if dragStartOffset == nil {
                    dragStartOffset = panOffset
                }
                let hiddenFraction = max(zoomLevel - 1, 0) / zoomLevel
                let delta = value.translation.width / max(width, 1)
                panOffset = clampPanOffset((dragStartOffset ?? panOffset) - delta * hiddenFraction)
            }
            .onEnded { _ in
                dragStartOffset = nil
            }
    }

    private func clampPanOffset(_ value: CGFloat) -> CGFloat {
        guard zoomLevel > 1 else { return 0 }
        return min(max(0, value), 1)
    }

    private func zoomWithScroll(deltaY: CGFloat, anchorRatio: CGFloat) {
        guard deltaY != 0 else { return }

        let totalDuration = max(dayEnd.timeIntervalSince(dayStart), 1)
        let oldZoom = zoomLevel
        let factor: CGFloat = deltaY < 0 ? 1.12 : 0.89
        let newZoom = min(max(1.0, oldZoom * factor), 20.0)
        guard abs(newZoom - oldZoom) > 0.001 else { return }

        let oldVisibleDuration = totalDuration / oldZoom
        let oldHidden = max(totalDuration - oldVisibleDuration, 0)
        let oldVisibleStart = dayStart.addingTimeInterval(oldHidden * Double(panOffset))
        let anchorDate = oldVisibleStart.addingTimeInterval(oldVisibleDuration * Double(anchorRatio))

        zoomLevel = newZoom

        let newVisibleDuration = totalDuration / newZoom
        let newHidden = max(totalDuration - newVisibleDuration, 0)

        guard newHidden > 0 else {
            panOffset = 0
            return
        }

        let desiredVisibleStart = anchorDate.timeIntervalSince(dayStart) - (newVisibleDuration * Double(anchorRatio))
        let normalizedOffset = CGFloat(desiredVisibleStart / newHidden)
        panOffset = clampPanOffset(normalizedOffset)
    }
}

private struct CommandScrollCaptureView: NSViewRepresentable {
    let onScroll: (NSEvent, CGPoint) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.postsFrameChangedNotifications = true
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onScroll = onScroll
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var onScroll: (NSEvent, CGPoint) -> Bool
        private weak var view: NSView?
        private var monitor: Any?

        init(onScroll: @escaping (NSEvent, CGPoint) -> Bool) {
            self.onScroll = onScroll
        }

        func attach(to view: NSView) {
            if self.view !== view {
                detach()
                self.view = view
            }

            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                guard let self, let view = self.view, let window = view.window, event.window === window else {
                    return event
                }

                let pointInWindow = event.locationInWindow
                let pointInView = view.convert(pointInWindow, from: nil)
                guard view.bounds.contains(pointInView) else {
                    return event
                }

                return self.onScroll(event, pointInView) ? nil : event
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            view = nil
        }

        deinit {
            detach()
        }
    }
}
