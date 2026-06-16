import SwiftData
import SwiftUI

struct WorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let workout: WorkoutRecord
    @State private var isConfirmingDelete = false
    @State private var isShowingDeleteError = false

    var body: some View {
        ZStack {
            TokyoTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    WorkoutRouteMap(route: workout.route, height: 260)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(workout.startDate, format: .dateTime.weekday(.wide).month(.wide).day())
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(TokyoTheme.primaryText)
                        Text(workout.startDate, format: .dateTime.hour().minute())
                            .font(.subheadline)
                            .foregroundStyle(TokyoTheme.secondaryText)
                    }

                    WorkoutMetricsCard(
                        distance: workout.distance,
                        duration: workout.duration,
                        averagePace: workout.averagePace,
                        elevationGain: workout.elevationGain
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(workout.activity.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete workout", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .accessibilityLabel("Workout options")
                }
                .tint(TokyoTheme.primaryText)
            }
        }
        .alert("Delete this workout?", isPresented: $isConfirmingDelete) {
            Button("Delete workout", role: .destructive, action: deleteWorkout)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the workout and its route from trackme. It cannot be undone.")
        }
        .alert("Could not delete workout", isPresented: $isShowingDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The workout is still in your history. Try again.")
        }
    }

    private func deleteWorkout() {
        modelContext.delete(workout)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            isShowingDeleteError = true
        }
    }
}
