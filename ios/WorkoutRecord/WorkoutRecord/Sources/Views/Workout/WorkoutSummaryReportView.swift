import SwiftUI
import Combine

/// 訓練完成報告視圖
struct WorkoutSummaryReportView: View {
    let workout: Workout
    @Environment(\.dismiss) private var dismiss
    @StateObject private var globalSettings = GlobalSettingsManager.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // 標題區域
                    headerSection
                    
                    // 訓練統計
                    statsSection
                    
                    // 動作詳情
                    exercisesSection
                }
                .padding()
            }
            .navigationTitle("訓練完成")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .font(.headline)
                }
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("訓練完成！")
                .font(.title)
                .fontWeight(.bold)
            
            Text(workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Stats Section
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("訓練統計")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                StatCard(
                    title: "訓練時長",
                    value: formatDuration(workout.duration ?? 0),
                    icon: "clock.fill",
                    color: .blue
                )
                
                StatCard(
                    title: "總容量",
                    value: globalSettings.formatWeight(workout.totalVolume),
                    icon: "chart.bar.fill",
                    color: .green
                )
                
                StatCard(
                    title: "總組數",
                    value: "\(workout.totalSets)",
                    icon: "list.number",
                    color: .orange
                )
                
                StatCard(
                    title: "動作數量",
                    value: "\(workout.totalExercises)",
                    icon: "figure.strengthtraining.traditional",
                    color: .purple
                )
            }
        }
    }
    
    // MARK: - Exercises Section
    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("動作詳情")
                .font(.headline)
                .fontWeight(.semibold)
            
            ForEach(workout.exercises) { exercise in
                ExerciseSummaryCard(exercise: exercise)
            }
        }
    }
    
    // MARK: - Personal Records Section
    private var personalRecordsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("個人記錄")
                .font(.headline)
                .fontWeight(.semibold)
            
            // 這裡可以顯示本次訓練中創建的新 PR
            Text("本次訓練中沒有創建新的個人記錄")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .italic()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Suggestions Section
    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("訓練建議")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                SuggestionRow(
                    icon: "lightbulb.fill",
                    text: "建議下次訓練時增加 5% 的重量",
                    color: .yellow
                )
                
                SuggestionRow(
                    icon: "clock.fill",
                    text: "組間休息時間可以縮短至 60 秒",
                    color: .blue
                )
                
                SuggestionRow(
                    icon: "heart.fill",
                    text: "記得補充水分和蛋白質",
                    color: .red
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Helper Methods
    private func formatDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        
        if hours > 0 {
            return "\(hours)小時\(mins)分鐘"
        } else {
            return "\(mins)分鐘"
        }
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

struct ExerciseSummaryCard: View {
    let exercise: WorkoutExercise
    @StateObject private var globalSettings = GlobalSettingsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(exercise.exercise?.name ?? exercise.exerciseName ?? "未知動作")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(exercise.sets.count) 組")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("總容量")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(globalSettings.formatWeight(exercise.totalVolume))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("平均重量")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(globalSettings.formatWeight(exercise.averageWeight))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            
            // 組數詳情
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(exercise.sets) { set in
                        SetBadge(set: set)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct SetBadge: View {
    let set: WorkoutSet
    @StateObject private var globalSettings = GlobalSettingsManager.shared
    
    var body: some View {
        VStack(spacing: 2) {
            Text(globalSettings.formatWeight(set.weight))
                .font(.caption)
                .fontWeight(.semibold)
            
            Text("\(set.reps) 次")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(set.isWarmup ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
        .cornerRadius(8)
    }
}

struct SuggestionRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
            
            Spacer()
        }
    }
}

// MARK: - Extensions
extension WorkoutExercise {
    var averageWeight: Double {
        guard !sets.isEmpty else { return 0 }
        let totalWeight = sets.reduce(0) { $0 + $1.weight }
        return totalWeight / Double(sets.count)
    }
}

// MARK: - Preview
struct WorkoutSummaryReportView_Previews: PreviewProvider {
    static var previews: some View {
        WorkoutSummaryReportView(workout: Workout.sampleWorkout)
    }
}

extension Workout {
    static let sampleWorkout = Workout(
        userId: UUID(),
        startedAt: Date(),
        endedAt: Date(),
        duration: 75,
        totalVolume: 2500,
        totalSets: 12,
        totalExercises: 4,
        exercises: [
            WorkoutExercise(
                workoutId: UUID(),
                exerciseId: UUID(),
                orderIndex: 0,
                sets: [
                    WorkoutSet(workoutExerciseId: UUID(), setNumber: 1, weight: 60, reps: 10),
                    WorkoutSet(workoutExerciseId: UUID(), setNumber: 2, weight: 65, reps: 8),
                    WorkoutSet(workoutExerciseId: UUID(), setNumber: 3, weight: 70, reps: 6)
                ]
            )
        ]
    )
}
