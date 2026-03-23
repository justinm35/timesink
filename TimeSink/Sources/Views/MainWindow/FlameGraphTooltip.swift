import SwiftUI

struct FlameGraphTooltip: View {
    let record: ActivityRecord
    let category: Category?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(AppColorHelper.color(for: record.appName, isIdle: record.isIdle))
                    .frame(width: 10, height: 10)

                Text(record.isIdle ? "Idle" : record.appName)
                    .font(.caption)
                    .fontWeight(.semibold)

                if let category {
                    CategoryBadge(category: category)
                }
            }

            if !record.isIdle {
                Text(record.detail ?? record.windowTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(timeRangeText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(durationText)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(10)
        .frame(maxWidth: 260, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private var timeRangeText: String {
        let start = DateFormatting.timeFormatter.string(from: record.startedAt)
        let end = record.endedAt.map(DateFormatting.timeFormatter.string(from:)) ?? "now"
        return "\(start) - \(end)"
    }

    private var durationText: String {
        let seconds = record.durationSeconds ?? max(0, Int(Date().timeIntervalSince(record.startedAt)))
        return DateFormatting.formatDuration(seconds: seconds)
    }
}
