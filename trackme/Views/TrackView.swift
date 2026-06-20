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
    @State private var mapFollowsUser = true
    @State private var trackAlert: TrackAlert?

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
        .alert(item: $trackAlert, content: alert)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                recenterMap()
                tracker.prepareForWorkout()
            }
        }
        .onChange(of: tracker.gpsStatus) { _, status in
            guard status == .ready, tracker.state == .idle else { return }
            followMapIfNeeded()
        }
        .onChange(of: tracker.route.count) {
            followMapIfNeeded()
        }
        .onChange(of: tracker.state) { oldState, state in
            guard oldState != .tracking, state == .tracking else { return }
            recenterMap()
        }
        .onChange(of: camera.positionedByUser) {
            if camera.positionedByUser {
                mapFollowsUser = false
            }
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
}

private extension TrackView {
    private func mapHeight(for availableHeight: CGFloat) -> CGFloat {
        let panelHeight: CGFloat = tracker.errorMessage == nil ? 320 : 374
        return min(410, max(250, availableHeight - panelHeight))
    }

    private func recenterMap() {
        mapFollowsUser = true
        moveMapToCurrentFocus()
    }

    private func followMapIfNeeded() {
        guard mapFollowsUser else { return }
        moveMapToCurrentFocus()
    }

    private func moveMapToCurrentFocus() {
        withAnimation(.easeInOut(duration: 0.3)) {
            camera = TrackMapCamera.position(focusing: tracker.mapFocusLocation)
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
        guard tracker.hasMeaningfulWorkout else {
            trackAlert = .tooShortToSave
            return
        }

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
            trackAlert = .saveFailure(snapshot)
            return
        }
        tracker.reset()
        onWorkoutSaved()
    }

    private func discardWorkout() {
        impact(.light)
        tracker.discard()
        tracker.prepareForWorkout()
        recenterMap()
    }

    private func openLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func alert(for alert: TrackAlert) -> Alert {
        switch alert {
        case .tooShortToSave:
            Alert(
                title: Text("Nothing to save yet"),
                message: Text("Move a little more to save this workout, or discard it."),
                primaryButton: .default(Text("Keep recording")),
                secondaryButton: .destructive(Text("Discard workout"), action: discardWorkout)
            )
        case .saveFailure(let snapshot):
            Alert(
                title: Text("Could not save workout"),
                message: Text("Your workout was not saved. Try again or discard it."),
                primaryButton: .default(Text("Try again")) {
                    Task { await persist(snapshot) }
                },
                secondaryButton: .destructive(Text("Discard workout"))
            )
        }
    }

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard hapticControls else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
