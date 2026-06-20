import CoreLocation
import SwiftUI

struct StartWorkoutButton: View {
    let activity: ActivityKind
    let authorizationStatus: CLAuthorizationStatus
    let displayStatus: LocationDisplayStatus
    let isReadyToStart: Bool
    let isRequestingAuthorization: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isRequestingAuthorization {
                    ProgressView()
                        .tint(TokyoTheme.background)
                } else {
                    Image(systemName: imageName)
                }
                Text(title)
            }
            .font(.headline)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(background)
            .clipShape(Capsule())
        }
        .disabled(isDisabled)
        .accessibilityIdentifier("start-workout")
    }

    private var title: String {
        if isRequestingAuthorization {
            return "Getting location..."
        }
        switch displayStatus {
        case .locationNeeded:
            return "Enable Location"
        case .locationOff:
            return "Location Off"
        case .finding:
            return "Finding GPS..."
        case .ready:
            return "Start \(activity.title)"
        case .weakSignal:
            return "Waiting for GPS..."
        case .signalLost:
            return "GPS Signal Lost"
        case .live, .paused:
            return "Start \(activity.title)"
        }
    }

    private var imageName: String {
        switch displayStatus {
        case .locationNeeded, .locationOff, .finding, .weakSignal, .signalLost:
            return "location.fill"
        case .ready, .live, .paused:
            return activity.systemImage
        }
    }

    private var background: Color {
        if authorizationStatus == .notDetermined || isReadyToStart {
            return TokyoTheme.cyan
        }
        if displayStatus == .weakSignal || displayStatus == .signalLost {
            return TokyoTheme.amber.opacity(0.20)
        }
        return TokyoTheme.raised
    }

    private var foreground: Color {
        if authorizationStatus == .notDetermined || isReadyToStart {
            return TokyoTheme.background
        }
        if displayStatus == .weakSignal || displayStatus == .signalLost {
            return TokyoTheme.amber
        }
        return TokyoTheme.secondaryText
    }

    private var isDisabled: Bool {
        if isRequestingAuthorization {
            return true
        }
        if authorizationStatus == .notDetermined {
            return false
        }
        return !isReadyToStart
    }
}

struct LocationErrorBanner: View {
    let message: String
    let showsSettingsButton: Bool
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.caption)

            if showsSettingsButton {
                Button("Open iPhone Settings", systemImage: "arrow.up.right.square", action: openSettings)
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(TokyoTheme.magenta)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(TokyoTheme.magenta.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
