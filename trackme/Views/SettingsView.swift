import SwiftUI

struct SettingsView: View {
    @Environment(HealthKitService.self) private var health
    @AppStorage(AppPreferenceKey.autoSyncHealth) private var autoSync = true
    @AppStorage(AppPreferenceKey.hapticControls) private var haptics = true

    var body: some View {
        ZStack {
            TokyoTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScreenHeader(
                        title: "Settings",
                        subtitle: "Apple Health, feedback, and privacy."
                    )
                    healthCard
                    preferences
                    privacyCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 96)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.red.opacity(0.86))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Apple Health")
                        .font(.headline)
                        .foregroundStyle(TokyoTheme.primaryText)
                    Text(health.isConnected ? "Saves new workouts" : "Not connected")
                        .font(.caption)
                        .foregroundStyle(health.isConnected ? TokyoTheme.cyan : TokyoTheme.secondaryText)
                }
                Spacer()
                if health.isConnected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TokyoTheme.cyan)
                }
            }

            Text("Save completed workouts, distance, and routes to Apple Health.")
                .font(.subheadline)
                .foregroundStyle(TokyoTheme.secondaryText)
                .lineSpacing(3)

            if !health.isConnected {
                Button(action: requestHealthAccess) {
                    HStack {
                        if health.isWorking { ProgressView().tint(TokyoTheme.background) }
                        Text(healthButtonTitle)
                    }
                    .font(.headline)
                    .foregroundStyle(TokyoTheme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(TokyoTheme.cyan)
                    .clipShape(Capsule())
                }
                .disabled(health.isWorking || !health.isAvailable)
            }

            if let message = health.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(TokyoTheme.secondaryText)
            }
        }
        .padding(20)
        .tokyoCard()
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(title: "Workout preferences")
                .padding(.bottom, 14)

            SettingToggle(
                title: "Auto-sync workouts",
                subtitle: health.isConnected
                    ? "Automatically add new workouts to Apple Health."
                    : "Connect Apple Health to turn on auto-sync.",
                systemImage: "arrow.triangle.2.circlepath",
                value: autoSyncBinding,
                isEnabled: health.isConnected
            )
            Divider().overlay(Color.white.opacity(0.06))
            SettingToggle(
                title: "Haptic feedback",
                subtitle: "Feel a tap when you use workout controls.",
                systemImage: "hand.tap",
                value: $haptics
            )
        }
        .padding(20)
        .tokyoCard()
    }

    private var privacyCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(TokyoTheme.violet)
            VStack(alignment: .leading, spacing: 5) {
                Text("Private by default")
                    .font(.headline)
                    .foregroundStyle(TokyoTheme.primaryText)
                Text(
                    "Your routes and workout history stay on this iPhone. "
                        + "If auto-sync is on, new workouts are also saved to Apple Health."
                )
                    .font(.subheadline)
                    .foregroundStyle(TokyoTheme.secondaryText)
            }
        }
        .padding(20)
        .tokyoCard()
    }

    private var healthButtonTitle: String {
        health.isAvailable ? "Connect Apple Health" : "Apple Health Unavailable"
    }

    private var autoSyncBinding: Binding<Bool> {
        Binding(
            get: { health.isConnected && autoSync },
            set: { autoSync = $0 }
        )
    }

    private func requestHealthAccess() {
        Task { await health.requestAccess() }
    }
}

private struct SettingToggle: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var value: Bool
    var isEnabled = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(TokyoTheme.cyan)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(TokyoTheme.primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(TokyoTheme.secondaryText)
            }
            .accessibilityHidden(true)

            Spacer(minLength: 10)

            Toggle("", isOn: $value)
                .labelsHidden()
                .accessibilityLabel(title)
                .accessibilityHint(subtitle)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .padding(.vertical, 14)
        .tint(TokyoTheme.cyan)
    }
}
