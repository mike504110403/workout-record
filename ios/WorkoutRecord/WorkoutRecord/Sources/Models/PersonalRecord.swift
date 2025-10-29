import Foundation

// MARK: - Personal Record

struct PersonalRecord: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let exerciseId: UUID
    var exercise: Exercise?
    var weight: Double        // PR 重量
    var reps: Int             // 次數
    var oneRepMax: Double     // 估算的 1RM
    let achievedAt: Date      // 達成日期
    let workoutId: UUID?      // 關聯的訓練 ID
    let createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        exerciseId: UUID,
        exercise: Exercise? = nil,
        weight: Double,
        reps: Int,
        oneRepMax: Double,
        achievedAt: Date = Date(),
        workoutId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.exerciseId = exerciseId
        self.exercise = exercise
        self.weight = weight
        self.reps = reps
        self.oneRepMax = oneRepMax
        self.achievedAt = achievedAt
        self.workoutId = workoutId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - PR Summary (按動作分組)

struct PRSummary: Identifiable {
    let id: UUID
    let exerciseId: UUID
    let exerciseName: String
    let primaryMuscleGroup: Exercise.PrimaryMuscleGroup?
    var currentPR: PersonalRecord?
    var prHistory: [PersonalRecord] = []
    
    var weight: Double? {
        currentPR?.weight
    }
    
    var reps: Int? {
        currentPR?.reps
    }
    
    var oneRepMax: Double? {
        currentPR?.oneRepMax
    }
    
    var achievedAt: Date? {
        currentPR?.achievedAt
    }
    
    init(
        id: UUID = UUID(),
        exerciseId: UUID,
        exerciseName: String,
        primaryMuscleGroup: Exercise.PrimaryMuscleGroup? = nil,
        currentPR: PersonalRecord? = nil,
        prHistory: [PersonalRecord] = []
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.primaryMuscleGroup = primaryMuscleGroup
        self.currentPR = currentPR
        self.prHistory = prHistory
    }
}

