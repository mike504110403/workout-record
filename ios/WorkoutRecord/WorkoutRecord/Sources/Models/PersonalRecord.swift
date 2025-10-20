import Foundation

struct PersonalRecord: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let exerciseId: UUID
    var exercise: Exercise?
    var recordType: RecordType
    var value: Double
    var reps: Int?  // Reps when the record was achieved
    let achievedAt: Date
    let workoutSetId: UUID?
    let createdAt: Date
    var updatedAt: Date
    
    enum RecordType: String, Codable, CaseIterable {
        case oneRM = "1rm"
        case maxWeight = "max_weight"
        case maxReps = "max_reps"
        case maxVolume = "max_volume"  // ⭐
        
        var displayName: String {
            switch self {
            case .oneRM: return "1RM"
            case .maxWeight: return "最大重量"
            case .maxReps: return "最大次數"
            case .maxVolume: return "最大容量"
            }
        }
    }
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        exerciseId: UUID,
        exercise: Exercise? = nil,
        recordType: RecordType,
        value: Double,
        reps: Int? = nil,
        achievedAt: Date = Date(),
        workoutSetId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.exerciseId = exerciseId
        self.exercise = exercise
        self.recordType = recordType
        self.value = value
        self.reps = reps
        self.achievedAt = achievedAt
        self.workoutSetId = workoutSetId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Personal Record Summary
struct PersonalRecordSummary: Identifiable {
    let id: UUID
    let exerciseName: String
    let oneRM: Double?
    let maxWeight: Double?
    let maxReps: Int?
    let maxVolume: Double?  // ⭐
    
    init(
        id: UUID = UUID(),
        exerciseName: String,
        oneRM: Double? = nil,
        maxWeight: Double? = nil,
        maxReps: Int? = nil,
        maxVolume: Double? = nil
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.oneRM = oneRM
        self.maxWeight = maxWeight
        self.maxReps = maxReps
        self.maxVolume = maxVolume
    }
}

