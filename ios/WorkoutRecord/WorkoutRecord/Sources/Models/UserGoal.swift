import Foundation

// MARK: - User Goal

struct UserGoal: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    var weeklyWorkoutGoal: Int           // 週訓練次數目標
    var targetWeight: Double?             // 目標體重
    var volumeGoals: VolumeGoals          // 各肌群容量目標
    var restDayReminder: Bool             // 休息日提醒
    let createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        weeklyWorkoutGoal: Int = 3,
        targetWeight: Double? = nil,
        volumeGoals: VolumeGoals = VolumeGoals(),
        restDayReminder: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.weeklyWorkoutGoal = weeklyWorkoutGoal
        self.targetWeight = targetWeight
        self.volumeGoals = volumeGoals
        self.restDayReminder = restDayReminder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Volume Goals

struct VolumeGoals: Codable {
    var chest: Double?      // 胸部週容量目標 (kg)
    var back: Double?       // 背部週容量目標
    var legs: Double?       // 腿部週容量目標
    var shoulders: Double?  // 肩部週容量目標
    var arms: Double?       // 手臂週容量目標
    var core: Double?       // 核心週容量目標
    
    init(
        chest: Double? = nil,
        back: Double? = nil,
        legs: Double? = nil,
        shoulders: Double? = nil,
        arms: Double? = nil,
        core: Double? = nil
    ) {
        self.chest = chest
        self.back = back
        self.legs = legs
        self.shoulders = shoulders
        self.arms = arms
        self.core = core
    }
    
    // 根據肌群獲取目標
    func goal(for muscleGroup: Exercise.PrimaryMuscleGroup) -> Double? {
        switch muscleGroup {
        case .chest: return chest
        case .back: return back
        case .legs: return legs
        case .shoulders: return shoulders
        case .arms: return arms
        case .core: return core
        @unknown default: return nil
        }
    }
    
    // 設定肌群目標
    mutating func setGoal(for muscleGroup: Exercise.PrimaryMuscleGroup, value: Double?) {
        switch muscleGroup {
        case .chest: chest = value
        case .back: back = value
        case .legs: legs = value
        case .shoulders: shoulders = value
        case .arms: arms = value
        case .core: core = value
        @unknown default: break
        }
    }
}

// MARK: - Goal Progress

struct GoalProgress {
    let current: Double
    let target: Double
    
    var percentage: Double {
        guard target > 0 else { return 0 }
        return (current / target) * 100
    }
    
    var isComplete: Bool {
        percentage >= 100
    }
    
    var remaining: Double {
        max(0, target - current)
    }
}

