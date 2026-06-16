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
                    LiveRouteMap(camera: $camera, tracker: tracker)
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
                    Task { persist(alert.snapshot) }
                },
                secondaryButton: .destructive(Text("Discard"))
            )
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                recenterMap()
            }
        }
        .onAppear(perform: recenterMap)
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
            Button(action: startWorkout) {
                HStack(spacing: 10) {
                    if tracker.isRequestingAuthorization {
                        ProgressView()
                            .tint(TokyoTheme.background)
                    } else {
                        Image(systemName: tracker.activity.systemImage)
                    }
                    Text(tracker.isRequestingAuthorization ? "Getting location..." : "Start \(tracker.activity.title)")
                }
                .font(.headline)
                .foregroundStyle(TokyoTheme.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(TokyoTheme.cyan)
                .clipShape(Capsule())
            }
            .disabled(tracker.isRequestingAuthorization)
            .accessibilityIdentifier("start-workout")

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
        camera = .userLocation(followsHeading: false, fallback: .automatic)
    }

    private func startWorkout() {
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

        persist(snapshot)
    }

    private func persist(_ snapshot: WorkoutSnapshot) {
        do {
            modelContext.insert(try WorkoutRecord(snapshot: snapshot))
            try modelContext.save()
        } catch {
            modelContext.rollback()
            tracker.reset()
            saveAlert = SaveAlert(snapshot: snapshot)
            return
        }
        tracker.reset()
        if autoSyncHealth {
            Task { await health.save(snapshot) }
        }
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
