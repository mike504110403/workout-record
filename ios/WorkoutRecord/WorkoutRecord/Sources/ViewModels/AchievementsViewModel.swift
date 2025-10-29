import Foundation
import Combine
import CoreData

/// 成就系統 ViewModel
class AchievementsViewModel: ObservableObject {
    @Published var achievements: [Achievement] = []
    @Published var isLoading = false
    @Published var newlyUnlockedAchievements: [Achievement] = []
    
    private let workoutRepository = WorkoutRepository()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadAchievements()
        checkAchievements()
    }
    
    // MARK: - Public Methods
    
    func refresh() {
        checkAchievements()
    }
    
    func achievements(for category: AchievementCategory) -> [Achievement] {
        achievements.filter { $0.category == category }
    }
    
    var totalAchievements: Int {
        achievements.count
    }
    
    var unlockedCount: Int {
        achievements.filter { $0.isUnlocked }.count
    }
    
    var completionPercentage: Double {
        guard totalAchievements > 0 else { return 0 }
        return Double(unlockedCount) / Double(totalAchievements) * 100
    }
    
    /// 是否有未查看的成就
    var hasUnseenAchievements: Bool {
        guard let lastViewed = UserDefaults.standard.object(forKey: "lastViewedAchievementsDate") as? Date else {
            // 如果從未查看，檢查是否有已解鎖的成就
            return unlockedCount > 0
        }
        
        // 檢查是否有在上次查看後解鎖的成就
        return achievements.contains { achievement in
            achievement.isUnlocked && 
            (achievement.unlockedAt ?? Date.distantPast) > lastViewed
        }
    }
    
    // MARK: - Private Methods
    
    private func loadAchievements() {
        // 載入預設成就列表
        achievements = Achievements.all
        
        // 從 UserDefaults 載入已解鎖狀態
        loadUnlockedStatus()
    }
    
    private func loadUnlockedStatus() {
        guard let data = UserDefaults.standard.data(forKey: "UnlockedAchievements"),
              let unlocked = try? JSONDecoder().decode([String: Date].self, from: data) else {
            return
        }
        
        for index in achievements.indices {
            if let unlockedDate = unlocked[achievements[index].id] {
                achievements[index].isUnlocked = true
                achievements[index].unlockedAt = unlockedDate
            }
        }
    }
    
    private func saveUnlockedStatus() {
        let unlocked = achievements
            .filter { $0.isUnlocked }
            .reduce(into: [String: Date]()) { result, achievement in
                result[achievement.id] = achievement.unlockedAt ?? Date()
            }
        
        if let data = try? JSONEncoder().encode(unlocked) {
            UserDefaults.standard.set(data, forKey: "UnlockedAchievements")
        }
    }
    
    /// 檢查並更新成就狀態
    private func checkAchievements() {
        Task {
            await MainActor.run {
                isLoading = true
            }
            
            // 獲取訓練數據
            let workouts = try? workoutRepository.fetchAll()
            guard let workouts = workouts else {
                await MainActor.run {
                    isLoading = false
                }
                return
            }
            
            var newlyUnlocked: [Achievement] = []
            
            // 檢查每個成就
            for index in achievements.indices {
                if achievements[index].isUnlocked {
                    continue  // 已解鎖的跳過
                }
                
                let (isCompleted, progress) = checkRequirement(
                    achievements[index].requirement,
                    workouts: workouts
                )
                
                achievements[index].progress = progress
                
                if isCompleted {
                    achievements[index].isUnlocked = true
                    achievements[index].unlockedAt = Date()
                    newlyUnlocked.append(achievements[index])
                }
            }
            
            await MainActor.run {
                if !newlyUnlocked.isEmpty {
                    self.newlyUnlockedAchievements = newlyUnlocked
                    self.saveUnlockedStatus()
                    
                    // 可以在這裡觸發通知或慶祝動畫
                    print("🎉 解鎖新成就: \(newlyUnlocked.map { $0.title }.joined(separator: ", "))")
                }
                
                self.isLoading = false
            }
        }
    }
    
    /// 檢查單個成就需求
    private func checkRequirement(
        _ requirement: AchievementRequirement,
        workouts: [Workout]
    ) -> (isCompleted: Bool, progress: Double) {
        switch requirement {
        case .workoutCount(let count):
            let current = workouts.count
            return (current >= count, min(Double(current) / Double(count), 1.0))
            
        case .singleWorkoutVolume(let targetVolume):
            let maxVolume = workouts.map { $0.totalVolume }.max() ?? 0
            return (maxVolume >= targetVolume, min(maxVolume / targetVolume, 1.0))
        
        case .totalVolume(let targetVolume):
            let totalVolume = workouts.reduce(0.0) { $0 + $1.totalVolume }
            return (totalVolume >= targetVolume, min(totalVolume / targetVolume, 1.0))
            
        case .consecutiveDays(let days):
            // 計算連續訓練天數
            let streak = calculateStreak(workouts: workouts)
            return (streak >= days, min(Double(streak) / Double(days), 1.0))
            
        case .oneRM(_, let targetWeight):
            // 從 PowerliftingViewModel 獲取
            // 這裡簡化處理，實際應該從數據庫查詢
            _ = targetWeight // 避免未使用警告
            return (false, 0.0)
            
        case .totalLifts(let targetTotal):
            _ = targetTotal // 避免未使用警告
            return (false, 0.0)
            
        case .weeklyGoal(let weeks):
            _ = weeks // 避免未使用警告
            return (false, 0.0)
            
        case .custom(_, let check):
            let isCompleted = check()
            return (isCompleted, isCompleted ? 1.0 : 0.0)
        }
    }
    
    /// 計算連續訓練天數
    private func calculateStreak(workouts: [Workout]) -> Int {
        guard !workouts.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        let sortedDates = workouts
            .compactMap { $0.startedAt }
            .map { calendar.startOfDay(for: $0) }
            .sorted(by: >)
        
        guard let latest = sortedDates.first else { return 0 }
        
        // 如果最新的訓練不是今天或昨天，連續記錄已中斷
        let today = calendar.startOfDay(for: Date())
        let daysSinceLatest = calendar.dateComponents([.day], from: latest, to: today).day ?? 0
        
        if daysSinceLatest > 1 {
            return 0
        }
        
        var streak = 1
        var currentDate = latest
        
        for date in sortedDates.dropFirst() {
            let daysDiff = calendar.dateComponents([.day], from: date, to: currentDate).day ?? 0
            
            if daysDiff == 1 {
                streak += 1
                currentDate = date
            } else {
                break
            }
        }
        
        return streak
    }
}

