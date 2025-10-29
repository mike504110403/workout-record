import SwiftUI
import Foundation
import Combine

/// 重構的訓練流程視圖
struct EnhancedWorkoutFlowView: View {
    @StateObject private var viewModel = EnhancedWorkoutFlowViewModel()
    @State private var currentExerciseIndex = 0
    @State private var currentSetIndex = 0
    @State private var showRestTimer = false
    @State private var showExerciseComplete = false
    @State private var showWorkoutComplete = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewModel.isWorkoutInProgress {
                    // 訓練進行中
                    workoutInProgressView
                } else {
                    // 開始訓練
                    startWorkoutView
                }
            }
            .navigationTitle("訓練")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.isWorkoutInProgress {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("結束") {
                            showWorkoutComplete = true
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .sheet(isPresented: $showRestTimer) {
                RestTimerView(
                    seconds: viewModel.currentRestTime,
                    exerciseName: currentExercise?.exercise?.name ?? ""
                )
            }
            .sheet(isPresented: $showExerciseComplete) {
                ExerciseCompleteView(
                    exercise: currentExercise!,
                    onNext: nextExercise,
                    onComplete: completeWorkout
                )
            }
            .sheet(isPresented: $showWorkoutComplete) {
                WorkoutCompleteView(
                    workout: viewModel.currentWorkout!,
                    onComplete: completeWorkout
                )
            }
        }
    }
    
    // MARK: - Start Workout View
    
    private var startWorkoutView: some View {
        VStack(spacing: 30) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("準備開始訓練")
                .font(.title)
                .fontWeight(.bold)
            
            Text("選擇你的訓練方式")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 16) {
                Button {
                    viewModel.startEmptyWorkout()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("開始空白訓練")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                
                Button {
                    viewModel.showTemplatePicker = true
                } label: {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("使用訓練模板")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $viewModel.showTemplatePicker) {
            TemplatePickerSheet { template in
                viewModel.startWorkoutFromTemplate(template)
            }
        }
    }
    
    // MARK: - Workout In Progress View
    
    private var workoutInProgressView: some View {
        VStack(spacing: 0) {
            // 進度指示器
            progressIndicator
            
            // 當前動作
            currentExerciseView
            
            // 當前組數
            currentSetView
            
            // 操作按鈕
            actionButtons
        }
    }
    
    // MARK: - Progress Indicator
    
    private var progressIndicator: some View {
        VStack(spacing: 8) {
            HStack {
                Text("動作 \(currentExerciseIndex + 1) / \(viewModel.exercises.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("組 \(currentSetIndex + 1) / \(currentExercise?.sets.count ?? 0)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            let progress = viewModel.exercises.count > 0 
                ? Double(currentExerciseIndex + 1) / Double(viewModel.exercises.count) 
                : 0.0
            SwiftUI.ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }
    
    // MARK: - Current Exercise View
    
    private var currentExerciseView: some View {
        VStack(spacing: 16) {
            if let exercise = currentExercise {
                Text(exercise.exercise?.name ?? "未知動作")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(exercise.exercise?.category?.name ?? "未知分類")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // 肌肉群標籤
                if let muscleGroups = exercise.exercise?.muscleGroups, !muscleGroups.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(muscleGroups, id: \.self) { muscleGroup in
                                Text(muscleGroup)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    // MARK: - Current Set View
    
    private var currentSetView: some View {
        VStack(spacing: 20) {
            if let exercise = currentExercise,
               currentSetIndex < exercise.sets.count {
                let set = exercise.sets[currentSetIndex]
                
                // 組數資訊
                VStack(spacing: 8) {
                    Text("第 \(currentSetIndex + 1) 組")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 30) {
                        VStack {
                            Text("\(Int(set.weight))")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                            Text("kg")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack {
                            Text("\(set.reps)")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                            Text("次")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // 完成按鈕
                Button {
                    completeCurrentSet()
                } label: {
                    Text("完成此組")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 16) {
            // 主要操作按鈕
            HStack(spacing: 16) {
                Button {
                    addNewSet()
                } label: {
                    VStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                        Text("新增組數")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(12)
                }
                
                Button {
                    startRestTimer()
                } label: {
                    VStack {
                        Image(systemName: "timer")
                            .font(.title2)
                        Text("休息計時")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .foregroundColor(.orange)
                    .cornerRadius(12)
                }
            }
            
            // 次要操作按鈕
            HStack(spacing: 16) {
                Button {
                    previousSet()
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("上一組")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                }
                .disabled(currentSetIndex == 0)
                
                Button {
                    nextSet()
                } label: {
                    HStack {
                        Text("下一組")
                        Image(systemName: "chevron.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                }
                .disabled(currentSetIndex >= (currentExercise?.sets.count ?? 0) - 1)
            }
        }
        .padding()
    }
    
    // MARK: - Computed Properties
    
    private var currentExercise: WorkoutExercise? {
        guard currentExerciseIndex < viewModel.exercises.count else { return nil }
        return viewModel.exercises[currentExerciseIndex]
    }
    
    // MARK: - Actions
    
    private func completeCurrentSet() {
        // 標記當前組數為完成
        viewModel.completeSet(exerciseIndex: currentExerciseIndex, setIndex: currentSetIndex)
        
        // 檢查是否完成所有組數
        if currentSetIndex >= (currentExercise?.sets.count ?? 0) - 1 {
            // 完成當前動作
            showExerciseComplete = true
        } else {
            // 下一組
            nextSet()
        }
    }
    
    private func addNewSet() {
        guard let exercise = currentExercise else { return }
        
        // 複製上一組的數據
        let lastSet = exercise.sets.last ?? WorkoutSet(
            workoutExerciseId: exercise.id,
            setNumber: 1,
            weight: 0,
            reps: 10,
            rpe: nil,
            restSeconds: nil,
            isWarmup: false,
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        let newSet = WorkoutSet(
            workoutExerciseId: exercise.id,
            setNumber: lastSet.setNumber + 1,
            weight: lastSet.weight,
            reps: lastSet.reps,
            rpe: lastSet.rpe,
            restSeconds: lastSet.restSeconds,
            isWarmup: lastSet.isWarmup,
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        viewModel.addSet(to: exercise, set: newSet)
        currentSetIndex = exercise.sets.count - 1
    }
    
    private func startRestTimer() {
        showRestTimer = true
    }
    
    private func previousSet() {
        if currentSetIndex > 0 {
            currentSetIndex -= 1
        }
    }
    
    private func nextSet() {
        if currentSetIndex < (currentExercise?.sets.count ?? 0) - 1 {
            currentSetIndex += 1
        }
    }
    
    private func nextExercise() {
        if currentExerciseIndex < viewModel.exercises.count - 1 {
            currentExerciseIndex += 1
            currentSetIndex = 0
        } else {
            completeWorkout()
        }
    }
    
    private func completeWorkout() {
        viewModel.completeWorkout()
        showWorkoutComplete = false
    }
}

// MARK: - Supporting Views

struct ExerciseCompleteView: View {
    let exercise: WorkoutExercise
    let onNext: () -> Void
    let onComplete: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                
                Text("\(exercise.exercise?.name ?? "未知動作") 完成！")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("恭喜完成這個動作")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                VStack(spacing: 16) {
                    Button {
                        onNext()
                    } label: {
                        Text("下一個動作")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    
                    Button {
                        onComplete()
                    } label: {
                        Text("完成訓練")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle("動作完成")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct WorkoutCompleteView: View {
    let workout: Workout
    let onComplete: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.yellow)
                
                Text("訓練完成！")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("恭喜完成今天的訓練")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // 訓練統計
                VStack(spacing: 16) {
                    StatRow(title: "訓練時長", value: "\(workout.duration ?? 0) 分鐘", icon: "clock")
                    StatRow(title: "總容量", value: "\(Int(workout.totalVolume)) kg", icon: "chart.bar")
                    StatRow(title: "總組數", value: "\(workout.totalSets)", icon: "list.number")
                    StatRow(title: "動作數量", value: "\(workout.totalExercises)", icon: "figure.strengthtraining.traditional")
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                
                Button {
                    onComplete()
                } label: {
                    Text("查看詳細報告")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle("訓練完成")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct StatRow: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(title)
                .font(.subheadline)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - View Model

class EnhancedWorkoutFlowViewModel: ObservableObject {
    @Published var isWorkoutInProgress = false
    @Published var exercises: [WorkoutExercise] = []
    @Published var currentWorkout: Workout?
    @Published var showTemplatePicker = false
    @Published var currentRestTime = 90
    
    private let workoutRepository = WorkoutRepository()
    private let exerciseRepository = ExerciseRepository()
    
    // MARK: - Workout Management
    
    func startEmptyWorkout() {
        isWorkoutInProgress = true
        exercises = []
        currentWorkout = Workout(
            userId: DataMigrationService.getCurrentUserId(),
            startedAt: Date(),
            endedAt: nil,
            duration: nil,
            totalVolume: 0,
            totalSets: 0,
            totalExercises: 0,
            note: nil,
            templateId: nil,
            exercises: [],
            createdAt: Date(),
            updatedAt: Date()
        )
    }
    
    func startWorkoutFromTemplate(_ template: TemplateInfo) {
        isWorkoutInProgress = true
        
        // 轉換模板為訓練動作
        exercises = template.exercises.map { templateExercise in
            let sets = (0..<(templateExercise.suggestedSets ?? 3)).map { setIndex in
                WorkoutSet(
                    workoutExerciseId: UUID(),
                    setNumber: setIndex + 1,
                    weight: 0,
                    reps: templateExercise.suggestedReps ?? 10,
                    restSeconds: 90,
                    isCompleted: false,
                    note: nil,
                    createdAt: Date(),
                    updatedAt: Date()
                )
            }
            
            return WorkoutExercise(
                workoutId: UUID(),
                exerciseId: templateExercise.exercise.id,
                exercise: templateExercise.exercise,
                orderIndex: 0,
                totalVolume: 0,
                totalSets: sets.count,
                note: nil,
                sets: sets,
                isCustomExercise: false,
                createdAt: Date(),
                updatedAt: Date()
            )
        }
        
        currentWorkout = Workout(
            userId: DataMigrationService.getCurrentUserId(),
            startedAt: Date(),
            endedAt: nil,
            duration: nil,
            totalVolume: 0,
            totalSets: 0,
            totalExercises: exercises.count,
            note: nil,
            templateId: template.id,
            exercises: exercises,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
    
    func addExercise(_ exercise: Exercise) {
        let workoutExercise = WorkoutExercise(
            workoutId: currentWorkout?.id ?? UUID(),
            exerciseId: exercise.id,
            exercise: exercise,
            orderIndex: exercises.count,
            totalVolume: 0,
            totalSets: 0,
            note: nil,
            sets: [],
            createdAt: Date(),
            updatedAt: Date()
        )
        
        exercises.append(workoutExercise)
        updateWorkoutStats()
    }
    
    func addSet(to exercise: WorkoutExercise, set: WorkoutSet) {
        if let index = exercises.firstIndex(where: { $0.id == exercise.id }) {
            exercises[index].sets.append(set)
            updateWorkoutStats()
        }
    }
    
    func completeSet(exerciseIndex: Int, setIndex: Int) {
        guard exerciseIndex < exercises.count,
              setIndex < exercises[exerciseIndex].sets.count else { return }
        
        exercises[exerciseIndex].sets[setIndex].isCompleted = true
        updateWorkoutStats()
    }
    
    func completeWorkout() {
        guard var workout = currentWorkout else { return }
        
        workout.endedAt = Date()
        workout.duration = Int(workout.endedAt!.timeIntervalSince(workout.startedAt) / 60)
        workout.exercises = exercises
        
        // 儲存到資料庫
        do {
            _ = try workoutRepository.create(workout: workout)
            print("✅ 訓練記錄已保存")
        } catch {
            print("❌ 儲存訓練記錄失敗: \(error.localizedDescription)")
        }
        
        // 重置狀態
        isWorkoutInProgress = false
        exercises = []
        currentWorkout = nil
    }
    
    private func updateWorkoutStats() {
        guard var workout = currentWorkout else { return }
        
        workout.totalVolume = exercises.reduce(0) { $0 + $1.totalVolume }
        workout.totalSets = exercises.reduce(0) { $0 + $1.sets.count }
        workout.totalExercises = exercises.count
        workout.exercises = exercises
        
        currentWorkout = workout
    }
}

#Preview {
    EnhancedWorkoutFlowView()
}
