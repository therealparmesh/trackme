import Charts
import SwiftData
import SwiftUI

struct InsightsView: View {
    enum Range: String, CaseIterable, Identifiable {
        case week = "1W"
        case month = "1M"
        case quarter = "1Q"
        var id: String { rawValue }

        func cutoffDate(relativeTo date: Date, calendar: Calendar) -> Date {
            let day = calendar.startOfDay(for: date)
            switch self {
            case .week:
                return calendar.date(byAdding: .day, value: -6, to: day) ?? .distantPast
            case .month:
                return calendar.date(byAdding: .day, value: -29, to: day) ?? .distantPast
            case .quarter:
                let month = calendar.dateInterval(of: .month, for: day)?.start ?? day
                return calendar.date(byAdding: .month, value: -2, to: month) ?? .distantPast
            }
        }

        func bucketStart(for date: Date, calendar: Calendar) -> Date {
            switch self {
            case .week:
                return calendar.startOfDay(for: date)
            case .month:
                return calendar.dateInterval(of: .weekOfYear, for: date)?.start
                    ?? calendar.startOfDay(for: date)
            case .quarter:
                return calendar.dateInterval(of: .month, for: date)?.start
                    ?? calendar.startOfDay(for: date)
            }
        }

        func bucketStarts(relativeTo date: Date, calendar: Calendar) -> [Date] {
            let end = calendar.startOfDay(for: date)
            let cutoff = cutoffDate(relativeTo: end, calendar: calendar)

            switch self {
            case .week:
                return (0..<7).compactMap {
                    calendar.date(byAdding: .day, value: $0, to: cutoff)
                }
            case .month:
                var result: [Date] = []
                var cursor = bucketStart(for: cutoff, calendar: calendar)
                while cursor <= end {
                    result.append(cursor)
                    guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
                    cursor = next
                }
                return result
            case .quarter:
                return (0..<3).compactMap {
                    calendar.date(byAdding: .month, value: $0, to: cutoff)
                }
            }
        }

        func axisLabel(for date: Date) -> String {
            switch self {
            case .week:
                return date.formatted(.dateTime.weekday(.abbreviated))
            case .month:
                return date.formatted(.dateTime.month(.abbreviated).day())
            case .quarter:
                return date.formatted(.dateTime.month(.abbreviated))
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .week: "Past 7 days"
            case .month: "Past 30 days"
            case .quarter: "Past 3 months"
            }
        }

        var chartTitle: String {
            switch self {
            case .week: "Distance by day"
            case .month: "Distance by week"
            case .quarter: "Distance by month"
            }
        }

        var barWidth: MarkDimension {
            switch self {
            case .week: .fixed(16)
            case .month: .fixed(24)
            case .quarter: .fixed(36)
            }
        }
    }

    @Query(sort: \WorkoutRecord.startDate, order: .reverse) private var workouts: [WorkoutRecord]
    @State private var range: Range = .week

    private var filtered: [WorkoutRecord] {
        let calendar = Calendar.current
        let cutoff = range.cutoffDate(relativeTo: Date(), calendar: calendar)
        return workouts.filter { $0.startDate >= cutoff }
    }

    private var chartData: [DistancePoint] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) {
            range.bucketStart(for: $0.startDate, calendar: calendar)
        }
        return range.bucketStarts(relativeTo: .now, calendar: calendar).map { date in
            let distance = grouped[date, default: []].reduce(0) { $0 + $1.distance }
            return DistancePoint(
                date: date,
                label: range.axisLabel(for: date),
                miles: distance / 1_609.344
            )
        }
    }

    private var totalDistance: Double { filtered.reduce(0) { $0 + $1.distance } }
    private var totalDuration: TimeInterval { filtered.reduce(0) { $0 + $1.duration } }
    private var chartUpperBound: Double {
        max(0.25, (chartData.map(\.miles).max() ?? 0) * 1.15)
    }

    var body: some View {
        TokyoScrollScreen(
            title: "History",
            subtitle: "See your distance, time, and workouts over time."
        ) {
            rangePicker
            summary
            recentWorkouts
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(Range.allCases) { item in
                Button(item.rawValue) { range = item }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(range == item ? TokyoTheme.background : TokyoTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(range == item ? TokyoTheme.cyan : Color.clear)
                    .clipShape(Capsule())
                    .accessibilityLabel(item.accessibilityLabel)
                    .accessibilityAddTraits(range == item ? .isSelected : [])
            }
        }
        .padding(4)
        .background(TokyoTheme.surface)
        .clipShape(Capsule())
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(MetricFormatter.distance(totalDistance))
                    .font(.system(size: 48, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("mi")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TokyoTheme.secondaryText)
            }
            .foregroundStyle(TokyoTheme.primaryText)

            HStack {
                MetricCell(label: "Workouts", value: "\(filtered.count)")
                MetricCell(label: "Moving time", value: MetricFormatter.duration(totalDuration))
            }

            Divider().overlay(Color.white.opacity(0.06))

            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: range.chartTitle)

                Chart(chartData) { point in
                    BarMark(
                        x: .value("Period", point.label),
                        y: .value("Miles", point.miles),
                        width: range.barWidth
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [TokyoTheme.cyan, TokyoTheme.violet],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: chartData.map(\.label)) { _ in
                        AxisValueLabel()
                            .foregroundStyle(TokyoTheme.secondaryText)
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.04))
                    }
                }
                .chartYScale(domain: 0...chartUpperBound)
                .chartYAxis(.hidden)
                .frame(height: 145)
                .overlay {
                    if totalDistance <= 0 {
                        VStack(spacing: 5) {
                            Image(systemName: "figure.walk")
                                .foregroundStyle(TokyoTheme.violet)
                            Text(
                                filtered.isEmpty
                                    ? "No workouts in this range"
                                    : "These workouts have no recorded distance"
                            )
                                .font(.caption.weight(.medium))
                                .foregroundStyle(TokyoTheme.secondaryText)
                        }
                        .offset(y: -8)
                    }
                }
            }
        }
        .padding(20)
        .tokyoCard()
    }

    private var recentWorkouts: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Recent workouts")

            if workouts.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "moon.stars.fill")
                        .foregroundStyle(TokyoTheme.violet)
                    Text("Your completed walks and runs will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(TokyoTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .tokyoCard()
            } else {
                ForEach(workouts.prefix(8)) { workout in
                    NavigationLink {
                        WorkoutDetailView(workout: workout)
                    } label: {
                        WorkoutRow(workout: workout)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct DistancePoint: Identifiable {
    let date: Date
    let label: String
    let miles: Double

    var id: Date { date }
}

private struct WorkoutRow: View {
    let workout: WorkoutRecord

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: workout.activity.systemImage)
                .font(.title3)
                .foregroundStyle(workout.activity == .run ? TokyoTheme.magenta : TokyoTheme.cyan)
                .frame(width: 46, height: 46)
                .background(TokyoTheme.raised)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(workout.activity.title)
                    .font(.headline)
                    .foregroundStyle(TokyoTheme.primaryText)
                Text(workout.startDate, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(TokyoTheme.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(MetricFormatter.distance(workout.distance)) mi")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(TokyoTheme.primaryText)
                Text(MetricFormatter.duration(workout.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(TokyoTheme.secondaryText)
            }
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(TokyoTheme.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .tokyoCard()
    }
}
