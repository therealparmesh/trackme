import SwiftUI

enum TokyoTheme {
    static let background = Color(red: 0.03, green: 0.04, blue: 0.10)
    static let surface = Color(red: 0.07, green: 0.09, blue: 0.17)
    static let raised = Color(red: 0.10, green: 0.12, blue: 0.22)
    static let cyan = Color(red: 0.47, green: 1.00, blue: 0.88)
    static let magenta = Color(red: 1.00, green: 0.42, blue: 0.74)
    static let violet = Color(red: 0.62, green: 0.55, blue: 1.00)
    static let primaryText = Color(red: 0.96, green: 0.97, blue: 1.00)
    static let secondaryText = Color(red: 0.57, green: 0.61, blue: 0.72)

    static let cardGradient = LinearGradient(
        colors: [surface, Color(red: 0.08, green: 0.08, blue: 0.16)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

enum AppPreferenceKey {
    static let autoSyncHealth = "autoSyncHealth"
    static let hapticControls = "hapticControls"
}

enum MetricFormatter {
    static func distance(_ meters: Double) -> String {
        String(format: "%.2f", meters / 1_609.344)
    }

    static func elevation(_ meters: Double) -> String {
        String(format: "%.0f", meters * 3.28084)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func pace(_ secondsPerMile: TimeInterval) -> String {
        guard secondsPerMile.isFinite, secondsPerMile > 0 else { return "--:--" }
        let value = Int(secondsPerMile.rounded())
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

struct TokyoCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(TokyoTheme.cardGradient)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func tokyoCard() -> some View {
        modifier(TokyoCard())
    }
}
