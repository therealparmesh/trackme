import MapKit
import SwiftData
import SwiftUI
import UIKit

struct TrackView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationTracker.self) private var tracker
    @Environment(HealthKitService.self) private var health
    @AppStorage(AppPreferenceKey.autoSyncHealth) private var autoSyncHealth = true
    @AppStorage(AppPreferenceKey.hapticControls) private var hapticControls = true
    let onWorkoutSaved: () -> Void
    @State private var camera: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
    @State private var saveAlert: SaveAlert?

    private var canOpenLocationSettings: Bool {
        tracker.authorizationStatus == .denied || tracker.authorizationStatus == .restricted
    }

    var body: some View {
        ZStack {
            TokyoTheme.background.ignoresSafeArea()

            GeometryReader { proxy in
                VStack(spacing: 0) {
                    LiveRouteMap(camera: $camera, tracker: tracker, recenter: recenterMap)
                        .frame(height: mapHeight(for: proxy.size.height))

                    trackingPanel
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert(item: $saveAlert) { alert in
            Alert(
                title: Text("Could not save workout"),
                message: Text("Your workout was not saved. Try again or discard it."),
                primaryButton: .default(Text("Try Again")) {
                    Task { await persist(alert.snapshot) }
                },
                secondaryButton: .destructive(Text("Discard"))
            )
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                recenterMap()
                tracker.prepareForWorkout()
            }
        }
        .onChange(of: tracker.gpsStatus) { _, status in
            guard status == .ready, tracker.state == .idle else { return }
            recenterMap()
        }
        .onAppear {
            recenterMap()
            tracker.prepareForWorkout()
        }
    }

    private var trackingPanel: some View {
        VStack(spacing: 22) {
            activityPicker

            VStack(spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text(MetricFormatter.distance(tracker.distance))
                        .font(.system(size: 58, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(TokyoTheme.primaryText)
                    Text("mi")
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(TokyoTheme.secondaryText)
                    Spacer()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Distance")
                .accessibilityValue("\(MetricFormatter.distance(tracker.distance)) miles")

                HStack {
                    MetricCell(label: "Moving time", value: MetricFormatter.duration(tracker.elapsed))
                    MetricCell(
                        label: "Average pace",
                        value: "\(MetricFormatter.pace(tracker.averagePace)) /mi"
                    )
                }
            }

            if let error = tracker.errorMessage {
                LocationErrorBanner(
                    message: error,
                    showsSettingsButton: canOpenLocationSettings,
                    openSettings: openLocationSettings
                )
            }

            controls
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(TokyoTheme.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var activityPicker: some View {
        @Bindable var tracker = tracker
        return HStack(spacing: 6) {
            ForEach(ActivityKind.allCases) { activity in
                Button {
                    tracker.activity = activity
                } label: {
                    Label(activity.title, systemImage: activity.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .padding(.vertical, 10)
                        .background(tracker.activity == activity ? TokyoTheme.raised : Color.clear)
                        .foregroundStyle(
                            tracker.activity == activity ? TokyoTheme.primaryText : TokyoTheme.secondaryText
                        )
                        .clipShape(Capsule())
                }
                .disabled(tracker.state != .idle)
                .accessibilityAddTraits(tracker.activity == activity ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch tracker.state {
        case .idle:
            StartWorkoutButton(
                activity: tracker.activity,
                authorizationStatus: tracker.authorizationStatus,
                displayStatus: tracker.displayStatus,
                isReadyToStart: tracker.isReadyToStart,
                isRequestingAuthorization: tracker.isRequestingAuthorization,
                action: startWorkout
            )

        case .tracking, .paused:
            HStack(spacing: 10) {
                Button(action: togglePause) {
                    Label(
                        tracker.state == .tracking ? "Pause" : "Resume",
                        systemImage: tracker.state == .tracking ? "pause.fill" : "play.fill"
                    )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(TokyoTheme.raised)
                        .foregroundStyle(TokyoTheme.primaryText)
                        .clipShape(Capsule())
                }
                .accessibilityLabel(tracker.state == .tracking ? "Pause workout" : "Resume workout")

                Button(action: saveWorkout) {
                    Label("Finish", systemImage: "stop.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(TokyoTheme.magenta)
                        .foregroundStyle(TokyoTheme.background)
                        .clipShape(Capsule())
                }
                .accessibilityLabel("Finish workout")
            }
        }
    }

    private func mapHeight(for availableHeight: CGFloat) -> CGFloat {
        let panelHeight: CGFloat = tracker.errorMessage == nil ? 320 : 374
        return min(410, max(250, availableHeight - panelHeight))
    }

    private func recenterMap() {
        let position: MapCameraPosition
        if let location = tracker.mapFocusLocation {
            position = .region(
                MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 750,
                    longitudinalMeters: 750
                )
            )
        } else {
            position = .userLocation(followsHeading: false, fallback: .automatic)
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            camera = position
        }
    }

    private func startWorkout() {
        guard tracker.authorizationStatus == .notDetermined || tracker.isReadyToStart else { return }
        impact(.medium)
        tracker.start()
    }

    private func togglePause() {
        impact(.light)
        if tracker.state == .tracking {
            tracker.pause()
        } else {
            tracker.resume()
        }
    }

    private func saveWorkout() {
        impact(.rigid)
        guard let snapshot = tracker.stop() else { return }

        Task {
            await persist(snapshot)
        }
    }

    private func persist(_ snapshot: WorkoutSnapshot) async {
        let healthKitWorkoutID = autoSyncHealth ? await health.save(snapshot) : nil
        do {
            modelContext.insert(try WorkoutRecord(
                snapshot: snapshot,
                healthKitWorkoutID: healthKitWorkoutID
            ))
            try modelContext.save()
        } catch {
            if let healthKitWorkoutID {
                await health.deleteWorkout(id: healthKitWorkoutID)
            }
            modelContext.rollback()
            tracker.reset()
            saveAlert = SaveAlert(snapshot: snapshot)
            return
        }
        tracker.reset()
        onWorkoutSaved()
    }

    private func openLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard hapticControls else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

private struct SaveAlert: Identifiable {
    let id = UUID()
    let snapshot: WorkoutSnapshot
}

private struct StartWorkoutButton: View {
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

private struct LocationErrorBanner: View {
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
