import SwiftData
import SwiftUI

struct WorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var health
    let workout: WorkoutRecord
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var isShowingDeleteError = false
    @State private var deleteErrorMessage = "The workout is still in your history. Try again."

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
            Text(deleteConfirmationMessage)
        }
        .alert("Could not delete workout", isPresented: $isShowingDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage)
        }
    }

    private var deleteConfirmationMessage: String {
        if workout.healthKitWorkoutID != nil {
            return "This removes the workout and route from trackme and Apple Health. It cannot be undone."
        }
        return "This removes the workout and route from trackme. It cannot be undone."
    }

    private func deleteWorkout() {
        guard !isDeleting else { return }
        isDeleting = true
        Task {
            await deleteWorkoutAndSyncHealth()
        }
    }

    private func deleteWorkoutAndSyncHealth() async {
        if let healthKitWorkoutID = workout.healthKitWorkoutID {
            let didDeleteFromHealth = await health.deleteWorkout(id: healthKitWorkoutID)
            guard didDeleteFromHealth else {
                isDeleting = false
                deleteErrorMessage = "The workout is still in your history and Apple Health was not changed. Try again."
                isShowingDeleteError = true
                return
            }
        }

        modelContext.delete(workout)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            deleteErrorMessage = workout.healthKitWorkoutID == nil
                ? "The workout is still in your history. Try again."
                : "The workout is still in your history, but its Apple Health copy may already be removed. Try again."
            isShowingDeleteError = true
        }
        isDeleting = false
    }
}
