import Foundation

struct Workout: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    var startedAt: Date
    var endedAt: Date?
    var duration: Int?  // in minutes
    var totalVolume: Double  // in kg (weight × reps × sets) ⭐
    var totalSets: Int  // ⭐
    var totalExercises: Int  // ⭐
    var note: String?
    var templateId: UUID?
    var exercises: [WorkoutExercise]
    let createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        duration: Int? = nil,
        totalVolume: Double = 0,
        totalSets: Int = 0,
        totalExercises: Int = 0,
        note: String? = nil,
        templateId: UUID? = nil,
        exercises: [WorkoutExercise] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.totalVolume = totalVolume
        self.totalSets = totalSets
        self.totalExercises = totalExercises
        self.note = note
        self.templateId = templateId
        self.exercises = exercises
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct WorkoutExercise: Identifiable, Codable {
    let id: UUID
    let workoutId: UUID
    let exerciseId: UUID
    var exercise: Exercise?
    var exerciseName: String?  // 新增：備用動作名稱
    var orderIndex: Int
    var totalVolume: Double  // ⭐
    var totalSets: Int  // ⭐
    var durationSeconds: Int?  // 新增：動作執行時間（秒）
    var note: String?
    var sets: [WorkoutSet]
    var isCustomExercise: Bool  // 新增：標識是否為自定義動作
    var isCompleted: Bool  // 新增：動作完成狀態
    let createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        workoutId: UUID,
        exerciseId: UUID,
        exercise: Exercise? = nil,
        exerciseName: String? = nil,
        orderIndex: Int,
        totalVolume: Double = 0,
        totalSets: Int = 0,
        durationSeconds: Int? = nil,
        note: String? = nil,
        sets: [WorkoutSet] = [],
        isCustomExercise: Bool = false,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.workoutId = workoutId
        self.exerciseId = exerciseId
        self.exercise = exercise
        self.exerciseName = exerciseName
        self.orderIndex = orderIndex
        self.totalVolume = totalVolume
        self.totalSets = totalSets
        self.durationSeconds = durationSeconds
        self.note = note
        self.sets = sets
        self.isCustomExercise = isCustomExercise
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct WorkoutSet: Identifiable, Codable {
    let id: UUID
    let workoutExerciseId: UUID
    var setNumber: Int
    var weight: Double  // in kg (主要儲存單位)
    var weightLb: Double  // in lb (輔助儲存單位)
    var reps: Int
    var volume: Double  // weight × reps ⭐
    var volumeLb: Double  // weightLb × reps (輔助容量)
    var rpe: Double?  // Rate of Perceived Exertion (1-10)
    var restSeconds: Int?
    var isWarmup: Bool
    var isCompleted: Bool  // 新增完成狀態
    var note: String?
    let createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        workoutExerciseId: UUID,
        setNumber: Int,
        weight: Double,
        reps: Int,
        rpe: Double? = nil,
        restSeconds: Int? = nil,
        isWarmup: Bool = false,
        isCompleted: Bool = false,
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.workoutExerciseId = workoutExerciseId
        self.setNumber = setNumber
        self.weight = weight
        self.weightLb = weight * 2.20462  // 自動轉換為磅
        self.reps = reps
        self.volume = weight * Double(reps)  // Auto calculate volume ⭐
        self.volumeLb = self.weightLb * Double(reps)  // 自動計算磅容量
        self.rpe = rpe
        self.restSeconds = restSeconds
        self.isWarmup = isWarmup
        self.isCompleted = isCompleted
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// Calculate and update volume for both units
    mutating func updateVolume() {
        self.volume = weight * Double(reps)
        self.volumeLb = weightLb * Double(reps)
    }
    
    /// Update weight and automatically convert to both units
    mutating func updateWeight(_ newWeight: Double, unit: User.WeightUnit) {
        switch unit {
        case .kg:
            self.weight = newWeight
            self.weightLb = newWeight * 2.20462
        case .lb:
            self.weightLb = newWeight
            self.weight = newWeight / 2.20462
        }
        updateVolume()
    }
}

// MARK: - Workout Summary (for lists and cards)
struct WorkoutSummary: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let duration: Int  // minutes
    let totalVolume: Double  // kg ⭐
    let totalSets: Int
    let exercisesCount: Int
    
    init(id: UUID, date: Date, duration: Int, totalVolume: Double, totalSets: Int, exercisesCount: Int) {
        self.id = id
        self.date = date
        self.duration = duration
        self.totalVolume = totalVolume
        self.totalSets = totalSets
        self.exercisesCount = exercisesCount
    }
}

// MARK: - Workout Template
struct WorkoutTemplate: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    var name: String
    var description: String?
    let isSystem: Bool
    var exercises: [WorkoutTemplateExercise]
    let createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        name: String,
        description: String? = nil,
        isSystem: Bool = false,
        exercises: [WorkoutTemplateExercise] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.description = description
        self.isSystem = isSystem
        self.exercises = exercises
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct WorkoutTemplateExercise: Identifiable, Codable {
    let id: UUID
    let templateId: UUID
    let exerciseId: UUID
    var exercise: Exercise?
    var orderIndex: Int
    var suggestedSets: Int?
    var suggestedReps: Int?
    var note: String?
    let createdAt: Date
    
    init(
        id: UUID = UUID(),
        templateId: UUID,
        exerciseId: UUID,
        exercise: Exercise? = nil,
        orderIndex: Int,
        suggestedSets: Int? = nil,
        suggestedReps: Int? = nil,
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.templateId = templateId
        self.exerciseId = exerciseId
        self.exercise = exercise
        self.orderIndex = orderIndex
        self.suggestedSets = suggestedSets
        self.suggestedReps = suggestedReps
        self.note = note
        self.createdAt = createdAt
    }
}

// MARK: - WorkoutTemplate Extensions
extension WorkoutTemplate {
    /// 計算預估時長（分鐘）
    var estimatedDuration: Int {
        // 每個動作預估 5 分鐘，每組預估 1 分鐘，休息時間預估 1 分鐘
        let exerciseTime = exercises.count * 5
        let totalSets = exercises.reduce(0) { $0 + ($1.suggestedSets ?? 3) }
        let restTime = totalSets * 1
        return exerciseTime + restTime
    }
    
    /// 計算總組數
    var totalSets: Int {
        return exercises.reduce(0) { $0 + ($1.suggestedSets ?? 3) }
    }
    
    /// 計算預估容量（kg）
    var estimatedVolume: Double {
        // 預估容量 = 建議組數 × 建議次數 × 預設重量
        return exercises.reduce(0) { total, exercise in
            let sets = exercise.suggestedSets ?? 3
            let reps = exercise.suggestedReps ?? 10
            let defaultWeight = 50.0 // 預設重量，實際應該從用戶歷史記錄中獲取
            return total + (Double(sets * reps) * defaultWeight)
        }
    }
}

