import Foundation
import SwiftUI

/// 成就分類
enum AchievementCategory: String, CaseIterable, Identifiable {
    case powerlifting = "力量成就"
    case volume = "容量成就"
    case consistency = "堅持成就"
    case special = "特殊成就"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .powerlifting: return "trophy.fill"
        case .volume: return "chart.bar.fill"
        case .consistency: return "flame.fill"
        case .special: return "star.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .powerlifting: return .orange
        case .volume: return .blue
        case .consistency: return .red
        case .special: return .purple
        }
    }
}

/// 成就需求類型
enum AchievementRequirement {
    case oneRM(PowerLift, Double)              // 單項 1RM 達到指定重量
    case totalLifts(Double)                    // 三項總和達到指定重量
    case singleWorkoutVolume(Double)           // 單次訓練容量
    case totalVolume(Double)                   // 累計訓練容量
    case consecutiveDays(Int)                  // 連續訓練天數
    case workoutCount(Int)                     // 完成訓練次數
    case weeklyGoal(Int)                       // 連續達成週目標次數
    case custom(String, () -> Bool)            // 自定義條件
}

/// 成就模型
struct Achievement: Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let category: AchievementCategory
    let requirement: AchievementRequirement
    var isUnlocked: Bool = false
    var unlockedAt: Date? = nil
    var progress: Double = 0  // 0-1 之間的進度
    
    /// 成就等級（根據難度）
    var tier: AchievementTier {
        // 可以根據 requirement 判斷難度
        .bronze  // 預設
    }
}

enum AchievementTier: String {
    case bronze = "銅"
    case silver = "銀"
    case gold = "金"
    case platinum = "白金"
    
    var color: Color {
        switch self {
        case .bronze: return .brown
        case .silver: return .gray
        case .gold: return .yellow
        case .platinum: return .cyan
        }
    }
}

/// 預設成就列表
struct Achievements {
    static let all: [Achievement] = [
        // 力量成就 - 深蹲
        Achievement(
            id: "squat_50kg",
            title: "深蹲入門",
            description: "深蹲 1RM 達到 50kg",
            icon: "🏋️",
            category: .powerlifting,
            requirement: .oneRM(.squat, 50)
        ),
        Achievement(
            id: "squat_100kg",
            title: "深蹲破百",
            description: "深蹲 1RM 達到 100kg",
            icon: "💪",
            category: .powerlifting,
            requirement: .oneRM(.squat, 100)
        ),
        Achievement(
            id: "squat_150kg",
            title: "深蹲高手",
            description: "深蹲 1RM 達到 150kg",
            icon: "🦵",
            category: .powerlifting,
            requirement: .oneRM(.squat, 150)
        ),
        
        // 力量成就 - 臥推
        Achievement(
            id: "bench_40kg",
            title: "臥推起步",
            description: "臥推 1RM 達到 40kg",
            icon: "💪",
            category: .powerlifting,
            requirement: .oneRM(.benchPress, 40)
        ),
        Achievement(
            id: "bench_60kg",
            title: "臥推進階",
            description: "臥推 1RM 達到 60kg",
            icon: "💪",
            category: .powerlifting,
            requirement: .oneRM(.benchPress, 60)
        ),
        Achievement(
            id: "bench_100kg",
            title: "臥推破百",
            description: "臥推 1RM 達到 100kg",
            icon: "🏆",
            category: .powerlifting,
            requirement: .oneRM(.benchPress, 100)
        ),
        
        // 力量成就 - 硬舉
        Achievement(
            id: "deadlift_60kg",
            title: "硬舉入門",
            description: "硬舉 1RM 達到 60kg",
            icon: "🏋️",
            category: .powerlifting,
            requirement: .oneRM(.deadlift, 60)
        ),
        Achievement(
            id: "deadlift_100kg",
            title: "硬舉破百",
            description: "硬舉 1RM 達到 100kg",
            icon: "💪",
            category: .powerlifting,
            requirement: .oneRM(.deadlift, 100)
        ),
        Achievement(
            id: "deadlift_200kg",
            title: "硬舉猛獸",
            description: "硬舉 1RM 達到 200kg",
            icon: "🦁",
            category: .powerlifting,
            requirement: .oneRM(.deadlift, 200)
        ),
        
        // 三項總和
        Achievement(
            id: "total_200kg",
            title: "200 俱樂部",
            description: "三項總和達到 200kg",
            icon: "🎯",
            category: .powerlifting,
            requirement: .totalLifts(200)
        ),
        Achievement(
            id: "total_300kg",
            title: "300 俱樂部",
            description: "三項總和達到 300kg",
            icon: "🏅",
            category: .powerlifting,
            requirement: .totalLifts(300)
        ),
        Achievement(
            id: "total_400kg",
            title: "400 俱樂部",
            description: "三項總和達到 400kg",
            icon: "🏆",
            category: .powerlifting,
            requirement: .totalLifts(400)
        ),
        
        // 容量成就
        Achievement(
            id: "volume_5000kg",
            title: "5噸挑戰",
            description: "單次訓練容量達 5,000kg",
            icon: "📊",
            category: .volume,
            requirement: .singleWorkoutVolume(5000)
        ),
        Achievement(
            id: "volume_10000kg",
            title: "萬公斤俱樂部",
            description: "單次訓練容量達 10,000kg",
            icon: "📈",
            category: .volume,
            requirement: .singleWorkoutVolume(10000)
        ),
        Achievement(
            id: "total_volume_100000kg",
            title: "百噸戰士",
            description: "累計訓練容量達 100,000kg",
            icon: "⚡",
            category: .volume,
            requirement: .totalVolume(100000)
        ),
        
        // 堅持成就
        Achievement(
            id: "first_workout",
            title: "新的開始",
            description: "完成第一次訓練",
            icon: "🌟",
            category: .special,
            requirement: .workoutCount(1)
        ),
        Achievement(
            id: "workout_10",
            title: "初心者",
            description: "完成 10 次訓練",
            icon: "💫",
            category: .consistency,
            requirement: .workoutCount(10)
        ),
        Achievement(
            id: "workout_50",
            title: "認真訓練者",
            description: "完成 50 次訓練",
            icon: "⭐",
            category: .consistency,
            requirement: .workoutCount(50)
        ),
        Achievement(
            id: "workout_100",
            title: "百練達人",
            description: "完成 100 次訓練",
            icon: "🌟",
            category: .consistency,
            requirement: .workoutCount(100)
        ),
        Achievement(
            id: "streak_7",
            title: "週度戰士",
            description: "連續 7 天訓練",
            icon: "🔥",
            category: .consistency,
            requirement: .consecutiveDays(7)
        ),
        Achievement(
            id: "streak_30",
            title: "月度勇士",
            description: "連續 30 天訓練",
            icon: "🔥🔥",
            category: .consistency,
            requirement: .consecutiveDays(30)
        ),
        Achievement(
            id: "weekly_goal_4",
            title: "目標達成",
            description: "連續 4 週達成訓練目標",
            icon: "🎯",
            category: .consistency,
            requirement: .weeklyGoal(4)
        )
    ]
}

