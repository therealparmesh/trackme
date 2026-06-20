import CoreLocation
import MapKit
import SwiftUI

struct LiveRouteMap: View {
    @Binding var camera: MapCameraPosition
    let tracker: LocationTracker
    let recenter: () -> Void

    var body: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            ForEach(RouteTrailStyle.lines(from: tracker.route)) { line in
                MapPolyline(coordinates: line.coordinates)
                    .stroke(
                        line.color.opacity(0.20),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round)
                    )
                MapPolyline(coordinates: line.coordinates)
                    .stroke(
                        line.color,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )
            }

            if let start = tracker.route.first?.coordinate {
                Annotation("Start", coordinate: start) {
                    Circle()
                        .fill(TokyoTheme.background)
                        .stroke(TokyoTheme.cyan, lineWidth: 3)
                        .frame(width: 14, height: 14)
                }
            }

            if tracker.authorizationStatus == .authorizedAlways || tracker.authorizationStatus == .authorizedWhenInUse {
                UserAnnotation(anchor: .center) { _ in
                    ZStack {
                        Circle()
                            .fill(TokyoTheme.cyan.opacity(0.22))
                            .frame(width: 30, height: 30)
                        Circle()
                            .fill(TokyoTheme.cyan)
                            .frame(width: 16, height: 16)
                            .overlay {
                                Circle()
                                    .stroke(Color.white, lineWidth: 3)
                            }
                    }
                    .accessibilityLabel("Current location")
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .ignoresSafeArea(edges: .top)
        .overlay {
            LinearGradient(
                colors: [TokyoTheme.background.opacity(0.72), .clear, TokyoTheme.background.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("trackme")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(TokyoTheme.cyan)
                    Text(statusDescription)
                        .font(.caption)
                        .foregroundStyle(TokyoTheme.primaryText.opacity(0.72))
                }
                Spacer()
                HStack(spacing: 7) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                        .shadow(
                            color: tracker.displayStatus == .live ? statusColor.opacity(0.7) : .clear,
                            radius: 7
                        )
                    Text(statusLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(TokyoTheme.primaryText)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(TokyoTheme.background.opacity(0.78))
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1)
                }
            }
            .padding(.horizontal, 20)
            .safeAreaPadding(.top, 12)
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: recenter) {
                Image(systemName: "location.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TokyoTheme.primaryText)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(Color.white.opacity(0.12), lineWidth: 1)
                    }
            }
                .accessibilityLabel("Recenter map")
                .padding(16)
        }
    }

    private var statusLabel: String {
        switch tracker.displayStatus {
        case .locationNeeded: "LOCATION"
        case .locationOff: "OFF"
        case .finding: "FINDING"
        case .ready: "READY"
        case .live: "LIVE"
        case .paused: "PAUSED"
        case .weakSignal: "WEAK GPS"
        case .signalLost: "GPS LOST"
        }
    }

    private var statusDescription: String {
        switch tracker.displayStatus {
        case .locationNeeded:
            return "Enable location to get ready"
        case .locationOff:
            return "Location access is off"
        case .finding:
            return "Finding GPS signal"
        case .ready:
            return "Ready to \(tracker.activity.title.lowercased())"
        case .live:
            return "Tracking your \(tracker.activity.title.lowercased())"
        case .paused:
            return "\(tracker.activity.title) paused"
        case .weakSignal:
            return "GPS signal is weak"
        case .signalLost:
            return "Waiting for GPS to return"
        }
    }

    private var statusColor: Color {
        switch tracker.displayStatus {
        case .locationNeeded, .locationOff:
            return TokyoTheme.secondaryText
        case .finding:
            return TokyoTheme.violet
        case .ready:
            return TokyoTheme.cyan
        case .live:
            return TokyoTheme.magenta
        case .paused:
            return TokyoTheme.violet
        case .weakSignal, .signalLost:
            return TokyoTheme.amber
        }
    }

}
