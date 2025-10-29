import SwiftUI

struct WorkoutDetailView: View {
    let workout: WorkoutSummary
    @State private var showEditMode = false
    @State private var showDeleteConfirmation = false
    @Environment(\.dismiss) var dismiss
    
    // ✅ 真實數據
    @State private var fullWorkout: Workout?
    @State private var workoutExercises: [WorkoutExerciseDetail] = []
    @State private var isLoading = true
    
    private let repository = WorkoutRepository()
    
    var body: some View {
        Group {
            if isLoading {
                    SwiftUI.ProgressView()
                        .overlay(
                            Text("載入中...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        )
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // Workout summary header
                        summaryCard
                        
                        // Volume chart (mini)
                        volumeBreakdownCard
                        
                        // Exercise list with sets
                        exercisesList
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("訓練詳情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showEditMode = true
                    } label: {
                        Label("編輯", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("刪除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("確定要刪除這次訓練？", isPresented: $showDeleteConfirmation) {
            Button("刪除", role: .destructive) {
                deleteWorkout()
            }
        }
        .onAppear {
            loadWorkoutDetail()
        }
    }
    
    // MARK: - Summary Card
    private var summaryCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.date.formatted(date: .long, time: .omitted))
                        .font(.headline)
                    Text(workout.date.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("總容量")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(VolumeCalculator.formatVolume(workout.totalVolume))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
            }
            
            Divider()
            
            HStack(spacing: 20) {
                StatItem(
                    icon: "clock",
                    label: "時長",
                    value: "\(workout.duration)",
                    unit: "分鐘"
                )
                
                Divider()
                    .frame(height: 40)
                
                StatItem(
                    icon: "figure.strengthtraining.traditional",
                    label: "動作",
                    value: "\(workout.exercisesCount)",
                    unit: "個"
                )
                
                Divider()
                    .frame(height: 40)
                
                StatItem(
                    icon: "chart.bar",
                    label: "組數",
                    value: "\(workout.totalSets)",
                    unit: "組"
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Volume Breakdown Card
    private var volumeBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("容量分布")
                .font(.headline)
            
            VStack(spacing: 8) {
                ForEach(workoutExercises) { exercise in
                    HStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                        
                        Text(exercise.exerciseName)
                            .font(.subheadline)
                        
                        Spacer()
                        
                        Text(VolumeCalculator.formatVolume(exercise.totalVolume))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        
                        Text("(\(String(format: "%.0f", exercise.percentage))%)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Exercises List
    private var exercisesList: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("動作明細")
                .font(.headline)
                .padding(.horizontal)
            
            ForEach(workoutExercises) { exercise in
                ExerciseDetailCard(exercise: exercise)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    /// ✅ 從 repository 加載真實數據
    private func loadWorkoutDetail() {
        isLoading = true
        
        do {
            guard let workout = try repository.fetchById(workout.id) else {
                print("❌ 找不到訓練記錄")
                isLoading = false
                return
            }
            
            fullWorkout = workout
            
            // 轉換為 UI 數據格式
            let totalVolume = workout.totalVolume
            
            workoutExercises = workout.exercises.map { workoutExercise in
                let percentage = totalVolume > 0 ? (workoutExercise.totalVolume / totalVolume) * 100 : 0
                
                let sets = workoutExercise.sets.map { set in
                    WorkoutSetDetail(
                        setNumber: set.setNumber,
                        weight: set.weight,
                        reps: set.reps,
                        volume: set.weight * Double(set.reps),
                        isWarmup: set.isWarmup
                    )
                }
                
                return WorkoutExerciseDetail(
                    id: workoutExercise.id,
                    exerciseName: workoutExercise.exercise?.name ?? workoutExercise.exerciseName ?? "未知動作",
                    totalVolume: workoutExercise.totalVolume,
                    percentage: percentage,
                    sets: sets
                )
            }
            
            print("✅ 載入訓練詳情: \(workoutExercises.count) 個動作")
        } catch {
            print("❌ 載入訓練詳情失敗: \(error)")
        }
        
        isLoading = false
    }
    
    /// 刪除訓練
    private func deleteWorkout() {
        do {
            try repository.delete(id: workout.id)
            NotificationCenter.default.post(name: .workoutCompleted, object: nil)
            dismiss()
        } catch {
            print("❌ 刪除訓練失敗: \(error)")
        }
    }
}

// MARK: - Exercise Detail Card
struct ExerciseDetailCard: View {
    let exercise: WorkoutExerciseDetail
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(exercise.exerciseName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(VolumeCalculator.formatVolume(exercise.totalVolume))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        
                        Text("\(exercise.sets.count) 組")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if isExpanded {
                VStack(spacing: 0) {
                    // Table header
                    HStack {
                        Text("組")
                            .frame(width: 40, alignment: .center)
                        Text("重量")
                            .frame(maxWidth: .infinity)
                        Text("次數")
                            .frame(maxWidth: .infinity)
                        Text("容量")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                    
                    // Sets
                    ForEach(exercise.sets) { set in
                        HStack {
                            // Set number
                            HStack(spacing: 4) {
                                Text("\(set.setNumber)")
                                if set.isWarmup {
                                    Image(systemName: "flame")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }
                            .frame(width: 40, alignment: .center)
                            
                            // Weight
                            Text(String(format: "%.0f kg", set.weight))
                                .frame(maxWidth: .infinity)
                            
                            // Reps
                            Text("\(set.reps)")
                                .frame(maxWidth: .infinity)
                            
                            // Volume
                            Text(String(format: "%.0f", set.volume))
                                .fontWeight(set.isWarmup ? .regular : .semibold)
                                .foregroundColor(set.isWarmup ? .secondary : .blue)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        
                        if set.id != exercise.sets.last?.id {
                            Divider()
                                .padding(.leading, 12)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Stat Item
struct StatItem: View {
    let icon: String
    let label: String
    let value: String
    let unit: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
            
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Supporting Models
struct WorkoutExerciseDetail: Identifiable {
    let id: UUID
    let exerciseName: String
    let totalVolume: Double
    let percentage: Double
    let sets: [WorkoutSetDetail]
}

struct WorkoutSetDetail: Identifiable {
    let id = UUID()
    let setNumber: Int
    let weight: Double
    let reps: Int
    let volume: Double
    let isWarmup: Bool
}

#Preview {
    NavigationStack {
        WorkoutDetailView(
            workout: WorkoutSummary(
                id: UUID(),
                date: Date(),
                duration: 75,
                totalVolume: 5760,
                totalSets: 13,
                exercisesCount: 3
            )
        )
    }
}

