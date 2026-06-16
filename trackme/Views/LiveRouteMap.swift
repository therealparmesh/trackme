import CoreLocation
import MapKit
import SwiftUI

struct LiveRouteMap: View {
    @Binding var camera: MapCameraPosition
    let tracker: LocationTracker

    var body: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            ForEach(Array(tracker.route.routeSegments.enumerated()), id: \.offset) { _, segment in
                if segment.count > 1 {
                    MapPolyline(coordinates: segment.map(\.coordinate))
                        .stroke(
                            TokyoTheme.cyan.opacity(0.18),
                            style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round)
                        )
                    MapPolyline(coordinates: segment.map(\.coordinate))
                        .stroke(
                            TokyoTheme.cyan,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                        )
                }
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
                        .shadow(color: tracker.state == .tracking ? TokyoTheme.magenta : .clear, radius: 7)
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
        switch tracker.state {
        case .idle: "READY"
        case .tracking: "LIVE"
        case .paused: "PAUSED"
        }
    }

    private var statusDescription: String {
        switch tracker.state {
        case .idle: "Ready to \(tracker.activity.title.lowercased())"
        case .tracking: "Tracking your \(tracker.activity.title.lowercased())"
        case .paused: "\(tracker.activity.title) paused"
        }
    }

    private var statusColor: Color {
        switch tracker.state {
        case .idle: TokyoTheme.secondaryText
        case .tracking: TokyoTheme.magenta
        case .paused: TokyoTheme.violet
        }
    }

    private func recenter() {
        withAnimation(.easeInOut(duration: 0.35)) {
            camera = .userLocation(followsHeading: false, fallback: .automatic)
        }
    }
}
