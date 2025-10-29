import Foundation
import Combine

@MainActor
class WorkoutViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isWorkoutInProgress = false
    @Published var currentWorkoutExercises: [WorkoutExerciseViewModel] = []
    @Published var totalVolume: Double = 0
    @Published var totalSets: Int = 0
    @Published var workoutDuration: String = "00:00"
    @Published var errorMessage: String?
    @Published var completedWorkout: Workout?
    @Published var showWorkoutReport = false
    
    // MARK: - Computed Properties
    
    /// 檢查是否所有動作都已完成（必須有組數記錄且標記為完成）
    var canCompleteWorkout: Bool {
        // 必須至少有一個動作
        guard !currentWorkoutExercises.isEmpty else { return false }
        
        // 所有動作都必須：1) 有至少一組記錄 AND 2) 標記為完成
        return currentWorkoutExercises.allSatisfy { exercise in
            !exercise.sets.isEmpty && exercise.isCompleted
        }
    }
    
    /// 檢查是否有未完成的動作
    var hasIncompleteExercises: Bool {
        return currentWorkoutExercises.contains { exercise in
            exercise.sets.isEmpty && !exercise.isCompleted
        }
    }
    
    // MARK: - Private Properties
    private var workoutStartTime: Date?
    private var timerCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private let repository = WorkoutRepository()
    private var lastSetCompletionTime: [UUID: Date] = [:] // 記錄每個動作最後一組的完成時間
    
    // MARK: - Public Methods
    func startWorkout() {
        isWorkoutInProgress = true
        workoutStartTime = Date()
        startTimer()
        
        // 開始空白訓練
        currentWorkoutExercises = []
        updateTotals()
    }
    
    func startWorkoutFromTemplate(_ template: TemplateInfo) {
        isWorkoutInProgress = true
        workoutStartTime = Date()
        startTimer()
        
        // Load exercises from template
        currentWorkoutExercises = template.exercises.map { exercise in
            WorkoutExerciseViewModel(
                id: UUID(),
                exerciseId: exercise.exercise.id, // ✅ 使用實際的 exercise ID
                exerciseName: exercise.exercise.name,
                sets: []
            )
        }
        
        updateTotals()
    }
    
    func completeWorkout() {
        stopTimer()
        saveWorkout { [weak self] workout in
            self?.completedWorkout = workout
            self?.showWorkoutReport = true
            self?.resetWorkout()
        }
    }
    
    func cancelWorkout() {
        stopTimer()
        // TODO: Show confirmation dialog
        resetWorkout()
    }
    
    func addSet(to exercise: WorkoutExerciseViewModel, weight: Double, reps: Int, rpe: Double?) {
        // 計算組間休息時間
        let currentTime = Date()
        var restSeconds: Int? = nil
        
        if let lastTime = lastSetCompletionTime[exercise.id] {
            // 計算距離上一組的時間差（秒）
            restSeconds = Int(currentTime.timeIntervalSince(lastTime))
        }
        
        let newSet = WorkoutSetViewModel(
            id: UUID(),
            setNumber: exercise.sets.count + 1,
            weight: weight,
            reps: reps,
            volume: weight * Double(reps),
            rpe: rpe,
            restSeconds: restSeconds,
            isWarmup: false
        )
        
        if let index = currentWorkoutExercises.firstIndex(where: { $0.id == exercise.id }) {
            currentWorkoutExercises[index].sets.append(newSet)
            // 更新最後一組完成時間
            lastSetCompletionTime[exercise.id] = currentTime
            updateTotals()
            objectWillChange.send() // 觸發視圖更新
        }
    }
    
    func addExercise(_ exercise: Exercise) {
        let newExercise = WorkoutExerciseViewModel(
            id: UUID(),
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            sets: []
        )
        
        // 插入到最前面，讓新動作排在最上面
        currentWorkoutExercises.insert(newExercise, at: 0)
    }
    
    func deleteExercise(_ exercise: WorkoutExerciseViewModel) {
        currentWorkoutExercises.removeAll { $0.id == exercise.id }
        updateTotals()
    }
    
    func deleteSet(_ set: WorkoutSetViewModel, from exercise: WorkoutExerciseViewModel) {
        if let exerciseIndex = currentWorkoutExercises.firstIndex(where: { $0.id == exercise.id }) {
            currentWorkoutExercises[exerciseIndex].sets.removeAll { $0.id == set.id }
            
            // Renumber sets
            for (index, _) in currentWorkoutExercises[exerciseIndex].sets.enumerated() {
                currentWorkoutExercises[exerciseIndex].sets[index].setNumber = index + 1
            }
            
            updateTotals()
        }
    }
    
    func completeExercise(_ exercise: WorkoutExerciseViewModel) {
        if let exerciseIndex = currentWorkoutExercises.firstIndex(where: { $0.id == exercise.id }) {
            currentWorkoutExercises[exerciseIndex].isCompleted = true
            objectWillChange.send() // 觸發視圖更新，確保 canCompleteWorkout 重新計算
        }
    }
    
    func toggleExerciseExpansion(_ exercise: WorkoutExerciseViewModel) {
        // This method can be used for future expansion functionality
        // For now, it's a placeholder
    }
    
    // MARK: - Private Methods
    private func startTimer() {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateDuration()
            }
    }
    
    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
    
    private func updateDuration() {
        guard let startTime = workoutStartTime else { return }
        let duration = Date().timeIntervalSince(startTime)
        let totalMinutes = Int(duration / 60) // 轉換為分鐘
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        
        if hours > 0 {
            workoutDuration = String(format: "%d:%02d", hours, minutes)
        } else {
            workoutDuration = String(format: "%02d", minutes)
        }
    }
    
    private func updateTotals() {
        totalVolume = currentWorkoutExercises.isEmpty ? 0.0 : currentWorkoutExercises.reduce(0) { $0 + $1.totalVolume }
        totalSets = currentWorkoutExercises.isEmpty ? 0 : currentWorkoutExercises.reduce(0) { $0 + $1.sets.filter { !$0.isWarmup }.count }
    }
    
    private func resetWorkout() {
        isWorkoutInProgress = false
        currentWorkoutExercises = []
        totalVolume = 0
        totalSets = 0
        workoutDuration = "00:00"
        workoutStartTime = nil
    }
    
    // MARK: - PR Tracking
    
    private func checkAndRecordPRs(workout: Workout, userId: UUID) {
        let prRepository = PersonalRecordRepository()
        var newPRCount = 0
        
        for exercise in workout.exercises {
            for set in exercise.sets {
                // 忽略熱身組
                if set.isWarmup {
                    continue
                }
                
                // 計算 1RM
                let oneRM = OneRMCalculator.calculate(weight: set.weight, reps: set.reps)
                
                do {
                    // 檢查是否為新 PR
                    let isNewPR = try prRepository.isNewPR(exerciseId: exercise.exerciseId, oneRepMax: oneRM)
                    
                    if isNewPR {
                        // 創建新 PR 記錄
                        let pr = PersonalRecord(
                            userId: userId,
                            exerciseId: exercise.exerciseId,
                            weight: set.weight,
                            reps: set.reps,
                            oneRepMax: oneRM,
                            achievedAt: workout.startedAt,
                            workoutId: workout.id
                        )
                        
                        _ = try prRepository.create(personalRecord: pr)
                        newPRCount += 1
                        print("🏆 新 PR！動作: \(exercise.exerciseId), 1RM: \(oneRM)kg")
                    }
                } catch {
                    print("❌ 檢查 PR 失敗: \(error)")
                }
            }
        }
        
        if newPRCount > 0 {
            print("🎉 本次訓練創造了 \(newPRCount) 個新 PR！")
        }
    }
    
    private func saveWorkout(completion: @escaping (Workout) -> Void = { _ in }) {
        guard let startTime = workoutStartTime else { return }
        let userId = DataMigrationService.getCurrentUserId()
        
        // 轉換 WorkoutExerciseViewModel 為 WorkoutExercise
        let exercises: [WorkoutExercise] = currentWorkoutExercises.enumerated().map { index, exerciseVM in
            let sets: [WorkoutSet] = exerciseVM.sets.map { setVM in
                WorkoutSet(
                    id: setVM.id,
                    workoutExerciseId: exerciseVM.id,
                    setNumber: setVM.setNumber,
                    weight: setVM.weight,
                    reps: setVM.reps,
                    rpe: setVM.rpe,
                    restSeconds: nil,
                    isWarmup: setVM.isWarmup,
                    note: nil,
                    createdAt: Date(),
                    updatedAt: Date()
                )
            }
            
            // 根據 exerciseId 查找對應的 Exercise 對象
            let exerciseRepository = ExerciseRepository()
            var exercise = try? exerciseRepository.fetchById(exerciseVM.exerciseId)
            var isCustom = false
            
            // 如果 exerciseRepository 中找不到，嘗試從 CustomExerciseStorage 加載
            if exercise == nil {
                exercise = CustomExerciseStorage.shared.getCustomExercise(id: exerciseVM.exerciseId)
                isCustom = exercise != nil
            } else {
                // 判斷是否為系統動作
                isCustom = !(exercise?.isSystem ?? true)
            }
            
            return WorkoutExercise(
                id: exerciseVM.id,
                workoutId: UUID(), // 會在創建時設置
                exerciseId: exerciseVM.exerciseId,
                exercise: exercise,
                exerciseName: exercise?.name ?? exerciseVM.exerciseName,
                orderIndex: index,
                totalVolume: exerciseVM.totalVolume,
                totalSets: exerciseVM.sets.count,
                note: nil,
                sets: sets,
                isCustomExercise: isCustom,
                isCompleted: exerciseVM.isCompleted,
                createdAt: Date(),
                updatedAt: Date()
            )
        }
        
        // 計算真實的訓練時長（分鐘）
        let actualDuration = Int(Date().timeIntervalSince(startTime) / 60)
        
        // 創建 Workout
        let workout = Workout(
            id: UUID(),
            userId: userId,
            startedAt: startTime,
            endedAt: Date(),
            duration: actualDuration,
            totalVolume: totalVolume,
            totalSets: totalSets,
            totalExercises: currentWorkoutExercises.count,
            note: nil,
            templateId: nil,
            exercises: exercises,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // 保存到資料庫
        do {
            _ = try repository.create(workout: workout)
            print("✅ 訓練記錄已保存")
            
            // 調試：檢查保存的數據
            for (index, ex) in workout.exercises.enumerated() {
                print("   動作 \(index+1): exerciseId=\(ex.exerciseId), name=\(ex.exercise?.name ?? "nil")")
            }
            
            // 檢查並記錄 PR
            checkAndRecordPRs(workout: workout, userId: userId)
            
            // 發送通知，通知其他頁面更新數據
            NotificationCenter.default.post(name: .workoutCompleted, object: nil)
            
            // 調用 completion
            completion(workout)
        } catch {
            errorMessage = "保存失敗: \(error.localizedDescription)"
            print("❌ 保存訓練記錄失敗: \(error)")
        }
    }
}

// MARK: - Supporting View Models

class WorkoutExerciseViewModel: Identifiable, ObservableObject {
    let id: UUID
    let exerciseId: UUID
    let exerciseName: String
    @Published var sets: [WorkoutSetViewModel]
    @Published var isCompleted: Bool = false  // 新增：動作完成狀態
    
    var totalVolume: Double {
        guard !sets.isEmpty else { return 0.0 }
        return sets.filter { !$0.isWarmup }.reduce(0) { $0 + $1.volume }
    }
    
    init(id: UUID, exerciseId: UUID, exerciseName: String, sets: [WorkoutSetViewModel], isCompleted: Bool = false) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.sets = sets
        self.isCompleted = isCompleted
    }
}

struct WorkoutSetViewModel: Identifiable {
    let id: UUID
    var setNumber: Int
    var weight: Double
    var reps: Int
    var volume: Double
    var rpe: Double?
    var restSeconds: Int? // 組間休息時間（秒）
    var isWarmup: Bool
    
    init(id: UUID, setNumber: Int, weight: Double, reps: Int, volume: Double, rpe: Double? = nil, restSeconds: Int? = nil, isWarmup: Bool) {
        self.id = id
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.volume = volume
        self.rpe = rpe
        self.restSeconds = restSeconds
        self.isWarmup = isWarmup
    }
}

