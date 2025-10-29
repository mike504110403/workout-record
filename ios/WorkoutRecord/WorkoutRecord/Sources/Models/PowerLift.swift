import Foundation

/// 經典三項力量訓練動作
enum PowerLift: String, CaseIterable, Identifiable, Codable {
    case squat = "深蹲"
    case benchPress = "槓鈴臥推"
    case deadlift = "硬舉"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .squat: return "figure.strengthtraining.traditional"
        case .benchPress: return "figure.mind.and.body"
        case .deadlift: return "figure.core.training"
        }
    }
    
    var color: String {
        switch self {
        case .squat: return "blue"
        case .benchPress: return "green"
        case .deadlift: return "red"
        }
    }
    
    /// 匹配動作名稱
    func matches(exerciseName: String) -> Bool {
        let lowercased = exerciseName.lowercased()
        switch self {
        case .squat:
            return lowercased.contains("深蹲") || lowercased.contains("squat")
        case .benchPress:
            return lowercased.contains("臥推") || lowercased.contains("bench press")
        case .deadlift:
            return lowercased.contains("硬舉") || lowercased.contains("deadlift")
        }
    }
}

/// 力量記錄
struct PowerLiftRecord: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let lift: PowerLift
    let weight: Double
    let reps: Int
    let oneRepMax: Double
    let achievedAt: Date
    let note: String?
    let createdAt: Date
    let updatedAt: Date
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        lift: PowerLift,
        weight: Double,
        reps: Int = 1,
        oneRepMax: Double? = nil,
        achievedAt: Date = Date(),
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.lift = lift
        self.weight = weight
        self.reps = reps
        // 如果沒有提供 oneRepMax，則使用重量計算（假設 1 次）
        self.oneRepMax = oneRepMax ?? OneRMCalculator.calculate(weight: weight, reps: reps)
        self.achievedAt = achievedAt
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

