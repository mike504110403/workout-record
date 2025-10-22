import Foundation

/// 經典三項力量訓練動作
enum PowerLift: String, CaseIterable, Identifiable {
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
struct PowerLiftRecord: Identifiable {
    let id: UUID
    let lift: PowerLift
    let weight: Double
    let reps: Int
    let oneRepMax: Double
    let achievedAt: Date
    let isManualEntry: Bool  // 是否為手動輸入的 PR
    
    init(
        id: UUID = UUID(),
        lift: PowerLift,
        weight: Double,
        reps: Int,
        oneRepMax: Double,
        achievedAt: Date,
        isManualEntry: Bool = false
    ) {
        self.id = id
        self.lift = lift
        self.weight = weight
        self.reps = reps
        self.oneRepMax = oneRepMax
        self.achievedAt = achievedAt
        self.isManualEntry = isManualEntry
    }
}

