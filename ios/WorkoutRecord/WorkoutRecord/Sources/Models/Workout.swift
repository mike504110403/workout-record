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
    var orderIndex: Int
    var totalVolume: Double  // ⭐
    var totalSets: Int  // ⭐
    var note: String?
    var sets: [WorkoutSet]
    let createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        workoutId: UUID,
        exerciseId: UUID,
        exercise: Exercise? = nil,
        orderIndex: Int,
        totalVolume: Double = 0,
        totalSets: Int = 0,
        note: String? = nil,
        sets: [WorkoutSet] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.workoutId = workoutId
        self.exerciseId = exerciseId
        self.exercise = exercise
        self.orderIndex = orderIndex
        self.totalVolume = totalVolume
        self.totalSets = totalSets
        self.note = note
        self.sets = sets
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct WorkoutSet: Identifiable, Codable {
    let id: UUID
    let workoutExerciseId: UUID
    var setNumber: Int
    var weight: Double  // in kg
    var reps: Int
    var volume: Double  // weight × reps ⭐
    var rpe: Double?  // Rate of Perceived Exertion (1-10)
    var restSeconds: Int?
    var isWarmup: Bool
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
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.workoutExerciseId = workoutExerciseId
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.volume = weight * Double(reps)  // Auto calculate volume ⭐
        self.rpe = rpe
        self.restSeconds = restSeconds
        self.isWarmup = isWarmup
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// Calculate and update volume
    mutating func updateVolume() {
        self.volume = weight * Double(reps)
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

