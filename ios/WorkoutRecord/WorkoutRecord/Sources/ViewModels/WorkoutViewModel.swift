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
    
    // MARK: - Private Properties
    private var workoutStartTime: Date?
    private var timerCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private let repository = WorkoutRepository()
    
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
        saveWorkout()
        resetWorkout()
    }
    
    func cancelWorkout() {
        stopTimer()
        // TODO: Show confirmation dialog
        resetWorkout()
    }
    
    func addSet(to exercise: WorkoutExerciseViewModel, weight: Double, reps: Int, rpe: Double?) {
        let newSet = WorkoutSetViewModel(
            id: UUID(),
            setNumber: exercise.sets.count + 1,
            weight: weight,
            reps: reps,
            volume: weight * Double(reps),
            rpe: rpe,
            isWarmup: false
        )
        
        if let index = currentWorkoutExercises.firstIndex(where: { $0.id == exercise.id }) {
            currentWorkoutExercises[index].sets.append(newSet)
            updateTotals()
        }
    }
    
    func addExercise(_ exercise: Exercise) {
        let newExercise = WorkoutExerciseViewModel(
            id: UUID(),
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            sets: []
        )
        
        currentWorkoutExercises.append(newExercise)
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
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        workoutDuration = String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func updateTotals() {
        totalVolume = currentWorkoutExercises.reduce(0) { $0 + $1.totalVolume }
        totalSets = currentWorkoutExercises.reduce(0) { $0 + $1.sets.filter { !$0.isWarmup }.count }
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
    
    private func saveWorkout() {
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
            
            return WorkoutExercise(
                id: exerciseVM.id,
                workoutId: UUID(), // 會在創建時設置
                exerciseId: exerciseVM.exerciseId,
                exercise: nil,
                orderIndex: index,
                totalVolume: exerciseVM.totalVolume,
                totalSets: exerciseVM.sets.count,
                note: nil,
                sets: sets,
                createdAt: Date(),
                updatedAt: Date()
            )
        }
        
        // 創建 Workout
        let workout = Workout(
            id: UUID(),
            userId: userId,
            startedAt: startTime,
            endedAt: Date(),
            duration: Int(Date().timeIntervalSince(startTime)),
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
    
    var totalVolume: Double {
        sets.filter { !$0.isWarmup }.reduce(0) { $0 + $1.volume }
    }
    
    init(id: UUID, exerciseId: UUID, exerciseName: String, sets: [WorkoutSetViewModel]) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.sets = sets
    }
}

struct WorkoutSetViewModel: Identifiable {
    let id: UUID
    var setNumber: Int
    var weight: Double
    var reps: Int
    var volume: Double
    var rpe: Double?
    var isWarmup: Bool
    
    init(id: UUID, setNumber: Int, weight: Double, reps: Int, volume: Double, rpe: Double? = nil, isWarmup: Bool) {
        self.id = id
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.volume = volume
        self.rpe = rpe
        self.isWarmup = isWarmup
    }
}

