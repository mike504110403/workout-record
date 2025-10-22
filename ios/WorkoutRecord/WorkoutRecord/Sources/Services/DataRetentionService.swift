import Foundation
import CoreData

/// 數據保留策略服務
/// 負責管理本地數據的保留期限
class DataRetentionService {
    static let shared = DataRetentionService()
    private let coreData = CoreDataStack.shared
    
    /// 本地資料保留天數（免費用戶）
    private let localRetentionDays = 30
    
    /// 檢查是否需要清理（每週執行一次）
    func scheduleCleanupIfNeeded() {
        let lastCleanup = UserDefaults.standard.object(forKey: "LastDataCleanup") as? Date
        let shouldClean = lastCleanup == nil ||
                         Date().timeIntervalSince(lastCleanup!) > 7 * 24 * 3600
        
        if shouldClean {
            Task {
                do {
                    try await cleanOldLocalData()
                    UserDefaults.standard.set(Date(), forKey: "LastDataCleanup")
                    print("✅ 數據清理完成")
                } catch {
                    print("❌ 數據清理失敗: \(error)")
                }
            }
        }
    }
    
    /// 清理超過保留期限的本地訓練數據
    func cleanOldLocalData() async throws {
        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -localRetentionDays,
            to: Date()
        )!
        
        print("🗑️ 開始清理 \(cutoffDate) 之前的訓練數據...")
        
        // 1. 刪除舊的訓練記錄
        try await deleteOldWorkouts(before: cutoffDate)
        
        // 2. 保留統計摘要（不刪除 PR 記錄）
        // PR 記錄會保留，因為用戶會想追蹤歷史最佳成績
        
        print("✅ 數據清理完成")
    }
    
    /// 刪除舊的訓練記錄
    private func deleteOldWorkouts(before date: Date) async throws {
        let context = coreData.newBackgroundContext()
        
        try await context.perform {
            // 查詢要刪除的訓練
            let fetchRequest = WorkoutEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "startedAt < %@", date as NSDate)
            
            let oldWorkouts = try context.fetch(fetchRequest)
            
            if oldWorkouts.isEmpty {
                print("ℹ️ 沒有需要清理的訓練記錄")
                return
            }
            
            print("🗑️ 將刪除 \(oldWorkouts.count) 筆訓練記錄")
            
            // 刪除訓練（會級聯刪除相關的動作和組數）
            for workout in oldWorkouts {
                context.delete(workout)
            }
            
            // 保存變更
            try self.coreData.save(context: context)
            
            print("✅ 成功刪除 \(oldWorkouts.count) 筆舊訓練記錄")
        }
    }
    
    /// 獲取當前數據庫統計
    func getDatabaseStats() -> DatabaseStats {
        do {
            let workoutCount = try coreData.count(WorkoutEntity.self)
            let bodyWeightCount = try coreData.count(BodyWeightEntity.self)
            let exerciseCount = try coreData.count(ExerciseEntity.self)
            let dbSize = coreData.getDatabaseSize()
            
            // 計算最舊的訓練記錄
            let context = coreData.viewContext
            let fetchRequest = WorkoutEntity.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: true)]
            fetchRequest.fetchLimit = 1
            
            let oldestWorkout = try? context.fetch(fetchRequest).first
            let oldestDate = oldestWorkout?.startedAt
            
            return DatabaseStats(
                workoutCount: workoutCount,
                bodyWeightCount: bodyWeightCount,
                exerciseCount: exerciseCount,
                databaseSize: dbSize,
                oldestWorkoutDate: oldestDate
            )
        } catch {
            print("❌ 無法獲取數據庫統計: \(error)")
            return DatabaseStats(
                workoutCount: 0,
                bodyWeightCount: 0,
                exerciseCount: 0,
                databaseSize: "未知",
                oldestWorkoutDate: nil
            )
        }
    }
    
    /// 手動觸發清理（供設定頁面使用）
    func manualCleanup() async throws {
        try await cleanOldLocalData()
    }
}

// MARK: - Database Stats

struct DatabaseStats {
    let workoutCount: Int
    let bodyWeightCount: Int
    let exerciseCount: Int
    let databaseSize: String
    let oldestWorkoutDate: Date?
    
    var retentionInfo: String {
        if let oldest = oldestWorkoutDate {
            let days = Calendar.current.dateComponents([.day], from: oldest, to: Date()).day ?? 0
            return "最舊記錄：\(days) 天前"
        } else {
            return "無訓練記錄"
        }
    }
}

