import MapKit
import SwiftUI

struct ScreenHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .foregroundStyle(TokyoTheme.primaryText)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(TokyoTheme.secondaryText)
        }
        .padding(.top, 18)
    }
}

struct SectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(TokyoTheme.primaryText)
    }
}

struct MetricCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(TokyoTheme.secondaryText)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(TokyoTheme.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkoutRouteMap: View {
    let route: [RoutePoint]
    let height: CGFloat

    var body: some View {
        if route.count > 1 {
            Map(interactionModes: [.pan, .zoom]) {
                ForEach(Array(route.routeSegments.enumerated()), id: \.offset) { _, segment in
                    if segment.count > 1 {
                        MapPolyline(coordinates: segment.map(\.coordinate))
                            .stroke(
                                TokyoTheme.cyan.opacity(0.18),
                                style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round)
                            )
                        MapPolyline(coordinates: segment.map(\.coordinate))
                            .stroke(
                                TokyoTheme.cyan,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                            )
                    }
                }

                if let start = route.first?.coordinate {
                    Annotation("Start", coordinate: start) {
                        routeMarker(color: TokyoTheme.cyan)
                    }
                }
                if let finish = route.last?.coordinate {
                    Annotation("Finish", coordinate: finish) {
                        routeMarker(color: TokyoTheme.magenta)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityLabel("Workout route")
        } else {
            VStack(spacing: 10) {
                Image(systemName: "map")
                    .font(.title2)
                    .foregroundStyle(TokyoTheme.violet)
                Text("Route unavailable")
                    .font(.headline)
                    .foregroundStyle(TokyoTheme.primaryText)
                Text("Not enough GPS points were recorded to draw this route.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(TokyoTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .tokyoCard()
        }
    }

    private func routeMarker(color: Color) -> some View {
        Circle()
            .fill(TokyoTheme.background)
            .stroke(color, lineWidth: 3)
            .frame(width: 14, height: 14)
    }
}

struct WorkoutMetricsCard: View {
    let distance: Double
    let duration: TimeInterval
    let averagePace: TimeInterval
    let elevationGain: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(title: "Summary")
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                alignment: .leading,
                spacing: 20
            ) {
                SummaryMetric(label: "Distance", value: "\(MetricFormatter.distance(distance)) mi")
                SummaryMetric(label: "Moving time", value: MetricFormatter.duration(duration))
                SummaryMetric(label: "Average pace", value: "\(MetricFormatter.pace(averagePace)) /mi")
                SummaryMetric(label: "Elevation gain", value: "\(MetricFormatter.elevation(elevationGain)) ft")
            }
        }
        .padding(20)
        .tokyoCard()
    }
}

private struct SummaryMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(TokyoTheme.secondaryText)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(TokyoTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
