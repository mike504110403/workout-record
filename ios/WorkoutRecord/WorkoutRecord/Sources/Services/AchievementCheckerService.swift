import Foundation
import Combine

/// 成就檢查服務
@MainActor
class AchievementCheckerService: ObservableObject {
    static let shared = AchievementCheckerService()
    
    @Published var unlockedAchievements: [Achievement] = []
    @Published var allAchievements: [Achievement] = []
    
    private let workoutRepository = WorkoutRepository()
    private let personalRecordRepository = PersonalRecordRepository()
    private let userGoalRepository = UserGoalRepository()
    
    private init() {
        loadAchievements()
    }
    
    // MARK: - Achievement Loading
    
    func loadAchievements() {
        allAchievements = Achievements.all.map { achievement in
            var updatedAchievement = achievement
            updatedAchievement.isUnlocked = checkAchievementUnlocked(achievement)
            updatedAchievement.progress = calculateAchievementProgress(achievement)
            return updatedAchievement
        }
        
        unlockedAchievements = allAchievements.filter { $0.isUnlocked }
    }
    
    // MARK: - Achievement Checking
    
    /// 檢查成就是否已解鎖
    private func checkAchievementUnlocked(_ achievement: Achievement) -> Bool {
        switch achievement.requirement {
        case .oneRM(let lift, let targetWeight):
            return checkOneRMAchievement(lift: lift, targetWeight: targetWeight)
        case .totalLifts(let targetTotal):
            return checkTotalLiftsAchievement(targetTotal: targetTotal)
        case .singleWorkoutVolume(let targetVolume):
            return checkSingleWorkoutVolumeAchievement(targetVolume: targetVolume)
        case .totalVolume(let targetVolume):
            return checkTotalVolumeAchievement(targetVolume: targetVolume)
        case .consecutiveDays(let targetDays):
            return checkConsecutiveDaysAchievement(targetDays: targetDays)
        case .workoutCount(let targetCount):
            return checkWorkoutCountAchievement(targetCount: targetCount)
        case .weeklyGoal(let targetWeeks):
            return checkWeeklyGoalAchievement(targetWeeks: targetWeeks)
        case .custom(_, let condition):
            return condition()
        }
    }
    
    /// 計算成就進度
    private func calculateAchievementProgress(_ achievement: Achievement) -> Double {
        switch achievement.requirement {
        case .oneRM(let lift, let targetWeight):
            return calculateOneRMProgress(lift: lift, targetWeight: targetWeight)
        case .totalLifts(let targetTotal):
            return calculateTotalLiftsProgress(targetTotal: targetTotal)
        case .singleWorkoutVolume(let targetVolume):
            return calculateSingleWorkoutVolumeProgress(targetVolume: targetVolume)
        case .totalVolume(let targetVolume):
            return calculateTotalVolumeProgress(targetVolume: targetVolume)
        case .consecutiveDays(let targetDays):
            return calculateConsecutiveDaysProgress(targetDays: targetDays)
        case .workoutCount(let targetCount):
            return calculateWorkoutCountProgress(targetCount: targetCount)
        case .weeklyGoal(let targetWeeks):
            return calculateWeeklyGoalProgress(targetWeeks: targetWeeks)
        case .custom(_, _):
            return achievement.isUnlocked ? 1.0 : 0.0
        }
    }
    
    // MARK: - Specific Achievement Checks
    
    /// 檢查 1RM 成就
    private func checkOneRMAchievement(lift: PowerLift, targetWeight: Double) -> Bool {
        do {
            let personalRecords = try personalRecordRepository.getAllPersonalRecords()
            let liftRecords = personalRecords.filter { record in
                // 這裡需要根據 lift 類型來篩選對應的動作
                // 暫時使用簡單的篩選邏輯
                return record.exerciseId == lift.exerciseId
            }
            
            // 檢查是否有達到目標重量的記錄
            return liftRecords.contains { record in
                record.oneRepMax >= targetWeight
            }
        } catch {
            print("❌ 檢查 1RM 成就失敗: \(error.localizedDescription)")
            return false
        }
    }
    
    /// 計算 1RM 進度
    private func calculateOneRMProgress(lift: PowerLift, targetWeight: Double) -> Double {
        do {
            let personalRecords = try personalRecordRepository.getAllPersonalRecords()
            let liftRecords = personalRecords.filter { record in
                return record.exerciseId == lift.exerciseId
            }
            
            guard let bestRecord = liftRecords.max(by: { $0.oneRepMax < $1.oneRepMax }) else {
                return 0.0
            }
            
            return min(bestRecord.oneRepMax / targetWeight, 1.0)
        } catch {
            return 0.0
        }
    }
    
    /// 檢查三項總和成就
    private func checkTotalLiftsAchievement(targetTotal: Double) -> Bool {
        do {
            let personalRecords = try personalRecordRepository.getAllPersonalRecords()
            
            // 獲取三大項的最佳記錄
            let squatRecord = personalRecords.filter { $0.exerciseId == PowerLift.squat.exerciseId }.max(by: { $0.oneRepMax < $1.oneRepMax })
            let benchRecord = personalRecords.filter { $0.exerciseId == PowerLift.benchPress.exerciseId }.max(by: { $0.oneRepMax < $1.oneRepMax })
            let deadliftRecord = personalRecords.filter { $0.exerciseId == PowerLift.deadlift.exerciseId }.max(by: { $0.oneRepMax < $1.oneRepMax })
            
            let squatMax = squatRecord?.oneRepMax ?? 0
            let benchMax = benchRecord?.oneRepMax ?? 0
            let deadliftMax = deadliftRecord?.oneRepMax ?? 0
            
            let total = squatMax + benchMax + deadliftMax
            return total >= targetTotal
        } catch {
            return false
        }
    }
    
    /// 計算三項總和進度
    private func calculateTotalLiftsProgress(targetTotal: Double) -> Double {
        do {
            let personalRecords = try personalRecordRepository.getAllPersonalRecords()
            
            let squatRecord = personalRecords.filter { $0.exerciseId == PowerLift.squat.exerciseId }.max(by: { $0.oneRepMax < $1.oneRepMax })
            let benchRecord = personalRecords.filter { $0.exerciseId == PowerLift.benchPress.exerciseId }.max(by: { $0.oneRepMax < $1.oneRepMax })
            let deadliftRecord = personalRecords.filter { $0.exerciseId == PowerLift.deadlift.exerciseId }.max(by: { $0.oneRepMax < $1.oneRepMax })
            
            let squatMax = squatRecord?.oneRepMax ?? 0
            let benchMax = benchRecord?.oneRepMax ?? 0
            let deadliftMax = deadliftRecord?.oneRepMax ?? 0
            
            let total = squatMax + benchMax + deadliftMax
            return min(total / targetTotal, 1.0)
        } catch {
            return 0.0
        }
    }
    
    /// 檢查單次訓練容量成就
    private func checkSingleWorkoutVolumeAchievement(targetVolume: Double) -> Bool {
        do {
            let workouts = try workoutRepository.getAllWorkouts()
            return workouts.contains { workout in
                workout.totalVolume >= targetVolume
            }
        } catch {
            return false
        }
    }
    
    /// 計算單次訓練容量進度
    private func calculateSingleWorkoutVolumeProgress(targetVolume: Double) -> Double {
        do {
            let workouts = try workoutRepository.getAllWorkouts()
            guard let maxVolume = workouts.map({ $0.totalVolume }).max() else {
                return 0.0
            }
            return min(maxVolume / targetVolume, 1.0)
        } catch {
            return 0.0
        }
    }
    
    /// 檢查累計訓練容量成就
    private func checkTotalVolumeAchievement(targetVolume: Double) -> Bool {
        do {
            let workouts = try workoutRepository.getAllWorkouts()
            let totalVolume = workouts.reduce(0) { $0 + $1.totalVolume }
            return totalVolume >= targetVolume
        } catch {
            return false
        }
    }
    
    /// 計算累計訓練容量進度
    private func calculateTotalVolumeProgress(targetVolume: Double) -> Double {
        do {
            let workouts = try workoutRepository.getAllWorkouts()
            let totalVolume = workouts.reduce(0) { $0 + $1.totalVolume }
            return min(totalVolume / targetVolume, 1.0)
        } catch {
            return 0.0
        }
    }
    
    /// 檢查連續訓練天數成就
    private func checkConsecutiveDaysAchievement(targetDays: Int) -> Bool {
        do {
            let workouts = try workoutRepository.getAllWorkouts()
            let consecutiveDays = calculateConsecutiveDays(from: workouts)
            return consecutiveDays >= targetDays
        } catch {
            return false
        }
    }
    
    /// 計算連續訓練天數進度
    private func calculateConsecutiveDaysProgress(targetDays: Int) -> Double {
        do {
            let workouts = try workoutRepository.getAllWorkouts()
            let consecutiveDays = calculateConsecutiveDays(from: workouts)
            return min(Double(consecutiveDays) / Double(targetDays), 1.0)
        } catch {
            return 0.0
        }
    }
    
    /// 檢查訓練次數成就
    private func checkWorkoutCountAchievement(targetCount: Int) -> Bool {
        do {
            let workouts = try workoutRepository.getAllWorkouts()
            return workouts.count >= targetCount
        } catch {
            return false
        }
    }
    
    /// 計算訓練次數進度
    private func calculateWorkoutCountProgress(targetCount: Int) -> Double {
        do {
            let workouts = try workoutRepository.getAllWorkouts()
            return min(Double(workouts.count) / Double(targetCount), 1.0)
        } catch {
            return 0.0
        }
    }
    
    /// 檢查週目標成就
    private func checkWeeklyGoalAchievement(targetWeeks: Int) -> Bool {
        // 這裡需要實現週目標檢查邏輯
        // 暫時返回 false
        return false
    }
    
    /// 計算週目標進度
    private func calculateWeeklyGoalProgress(targetWeeks: Int) -> Double {
        // 這裡需要實現週目標進度計算邏輯
        // 暫時返回 0.0
        return 0.0
    }
    
    // MARK: - Helper Methods
    
    /// 計算連續訓練天數
    private func calculateConsecutiveDays(from workouts: [Workout]) -> Int {
        guard !workouts.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        let sortedWorkouts = workouts.sorted { $0.startedAt > $1.startedAt }
        
        var consecutiveDays = 0
        var currentDate = Date()
        
        for workout in sortedWorkouts {
            let workoutDate = calendar.startOfDay(for: workout.startedAt)
            let currentDay = calendar.startOfDay(for: currentDate)
            
            if workoutDate == currentDay {
                consecutiveDays += 1
                currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate
            } else if workoutDate < currentDay {
                break
            }
        }
        
        return consecutiveDays
    }
    
    // MARK: - Public Methods
    
    /// 檢查新解鎖的成就
    func checkForNewAchievements() {
        let previousUnlockedCount = unlockedAchievements.count
        loadAchievements()
        
        let newUnlockedCount = unlockedAchievements.count
        if newUnlockedCount > previousUnlockedCount {
            // 有新成就解鎖
            let newAchievements = unlockedAchievements.suffix(newUnlockedCount - previousUnlockedCount)
            for achievement in newAchievements {
                showAchievementNotification(achievement)
            }
        }
    }
    
    /// 顯示成就通知
    private func showAchievementNotification(_ achievement: Achievement) {
        // 這裡可以實現成就通知邏輯
        print("🎉 新成就解鎖: \(achievement.title)")
        
        // 可以發送通知
        NotificationCenter.default.post(
            name: .achievementUnlocked,
            object: achievement
        )
    }
    
    /// 獲取成就統計
    func getAchievementStats() -> AchievementStats {
        let totalAchievements = allAchievements.count
        let unlockedCount = unlockedAchievements.count
        let completionRate = totalAchievements > 0 ? Double(unlockedCount) / Double(totalAchievements) : 0.0
        
        return AchievementStats(
            totalAchievements: totalAchievements,
            unlockedCount: unlockedCount,
            completionRate: completionRate,
            recentUnlocks: unlockedAchievements.suffix(5).map { $0 }
        )
    }
}

// MARK: - Supporting Types

struct AchievementStats {
    let totalAchievements: Int
    let unlockedCount: Int
    let completionRate: Double
    let recentUnlocks: [Achievement]
}

// MARK: - Notifications

extension Notification.Name {
    static let achievementUnlocked = Notification.Name("achievementUnlocked")
}

// MARK: - PowerLift Extension

extension PowerLift {
    var exerciseId: UUID {
        // 這裡需要根據實際的動作 ID 來映射
        // 暫時使用固定的 UUID
        switch self {
        case .squat:
            return UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
        case .benchPress:
            return UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID()
        case .deadlift:
            return UUID(uuidString: "00000000-0000-0000-0000-000000000003") ?? UUID()
        }
    }
}
