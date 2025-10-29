import Foundation
import CoreData

/// 數據遷移服務
/// 負責將現有的 Mock 數據遷移到 CoreData
class DataMigrationService {
    
    private let coreData = CoreDataStack.shared
    
    // MARK: - Check Migration Status
    
    /// 檢查是否已完成遷移
    func hasMigrated() -> Bool {
        return UserDefaults.standard.bool(forKey: "CoreDataMigrationCompleted")
    }
    
    /// 標記遷移完成
    func markMigrationComplete() {
        UserDefaults.standard.set(true, forKey: "CoreDataMigrationCompleted")
    }
    
    // MARK: - Initialize Default Data
    
    /// 初始化默認數據（系統動作、示例模板等）
    func initializeDefaultData() async throws {
        // 檢查是否已初始化
        if UserDefaults.standard.bool(forKey: "DefaultDataInitialized") {
            print("✅ 默認數據已初始化，跳過")
            return
        }
        
        print("🔄 開始初始化默認數據...")
        
        // 1. 創建默認用戶（暫時，未來會有真實登入）
        let userId = try createDefaultUser()
        
        // 2. 初始化系統動作庫
        try initializeSystemExercises()
        
        // 3. 創建示例模板
        try createSampleTemplates(userId: userId)
        
        // 標記完成
        UserDefaults.standard.set(true, forKey: "DefaultDataInitialized")
        print("✅ 默認數據初始化完成")
    }
    
    // MARK: - Helper Methods
    
    /// 創建默認用戶
    private func createDefaultUser() throws -> UUID {
        let context = coreData.viewContext
        
        // 檢查是否已存在用戶
        let fetchRequest = UserEntity.fetchRequest()
        if let existingUser = try context.fetch(fetchRequest).first {
            return existingUser.id ?? UUID()
        }
        
        // 創建新用戶
        let user = UserEntity(context: context)
        let userId = UUID()
        user.id = userId
        user.name = "健身愛好者"
        user.createdAt = Date()
        user.updatedAt = Date()
        
        try coreData.save(context: context)
        
        // 保存用戶 ID 供全局使用
        UserDefaults.standard.set(userId.uuidString, forKey: "CurrentUserId")
        
        print("✅ 創建默認用戶: \(userId)")
        return userId
    }
    
    /// 初始化系統動作庫
    private func initializeSystemExercises() throws {
        let repository = ExerciseRepository()
        
        print("🔄 開始初始化系統動作庫...")
        
        // 從 MockData 獲取所有系統動作
        let allExercises = MockData.allExercises
        
        // 批量創建
        try repository.batchCreate(exercises: allExercises)
        
        print("✅ 成功初始化 \(allExercises.count) 個系統動作")
    }
    
    /// 創建示例模板
    private func createSampleTemplates(userId: UUID) throws {
        let repository = TemplateRepository()
        let exerciseRepo = ExerciseRepository()
        
        print("🔄 開始創建示例模板...")
        
        // 獲取一些常用動作
        let allExercises = try exerciseRepo.fetchSystemExercises()
        
        // 輔助函數：根據名稱查找動作
        func findExercise(name: String) -> Exercise? {
            return allExercises.first { $0.name == name || $0.nameEn == name }
        }
        
        // 輔助函數：創建 TemplateExercise
        func makeTemplateExercise(name: String, sets: Int, reps: Int) -> TemplateInfo.TemplateExercise? {
            guard let exercise = findExercise(name: name) else {
                print("⚠️ 找不到動作: \(name)")
                return nil
            }
            return TemplateInfo.TemplateExercise(
                id: exercise.id,
                exercise: exercise,
                suggestedSets: sets,
                suggestedReps: reps
            )
        }
        
        // 1. PPL - Push
        if let benchPress = makeTemplateExercise(name: "槓鈴臥推", sets: 4, reps: 8),
           let inclinePress = makeTemplateExercise(name: "上斜啞鈴臥推", sets: 4, reps: 10),
           let shoulderPress = makeTemplateExercise(name: "肩推", sets: 4, reps: 10),
           let lateralRaise = makeTemplateExercise(name: "側平舉", sets: 3, reps: 12),
           let tricepPushdown = makeTemplateExercise(name: "三頭下壓", sets: 3, reps: 12) {
            
            let pplPush = TemplateInfo(
                id: UUID(),
                name: "PPL - Push (推)",
                description: "胸、肩、三頭訓練",
                exercises: [benchPress, inclinePress, shoulderPress, lateralRaise, tricepPushdown],
                isSystem: true
            )
            _ = try repository.create(template: pplPush, userId: userId)
        }
        
        // 2. PPL - Pull
        if let deadlift = makeTemplateExercise(name: "硬舉", sets: 3, reps: 5),
           let pullup = makeTemplateExercise(name: "引體向上", sets: 4, reps: 8),
           let barbellRow = makeTemplateExercise(name: "槓鈴划船", sets: 4, reps: 10),
           let seatedRow = makeTemplateExercise(name: "坐姿划船", sets: 3, reps: 12),
           let barbellCurl = makeTemplateExercise(name: "槓鈴彎舉", sets: 3, reps: 10) {
            
            let pplPull = TemplateInfo(
                id: UUID(),
                name: "PPL - Pull (拉)",
                description: "背、二頭訓練",
                exercises: [deadlift, pullup, barbellRow, seatedRow, barbellCurl],
                isSystem: true
            )
            _ = try repository.create(template: pplPull, userId: userId)
        }
        
        // 3. PPL - Legs
        if let squat = makeTemplateExercise(name: "深蹲", sets: 4, reps: 8),
           let rdl = makeTemplateExercise(name: "羅馬尼亞硬舉", sets: 4, reps: 10),
           let legPress = makeTemplateExercise(name: "腿推機", sets: 4, reps: 12),
           let legCurl = makeTemplateExercise(name: "腿彎舉", sets: 3, reps: 12),
           let calfRaise = makeTemplateExercise(name: "提踵", sets: 4, reps: 15) {
            
            let pplLegs = TemplateInfo(
                id: UUID(),
                name: "PPL - Legs (腿)",
                description: "腿部完整訓練",
                exercises: [squat, rdl, legPress, legCurl, calfRaise],
                isSystem: true
            )
            _ = try repository.create(template: pplLegs, userId: userId)
        }
        
        // 4. 全身訓練
        if let squat = makeTemplateExercise(name: "深蹲", sets: 3, reps: 10),
           let benchPress = makeTemplateExercise(name: "槓鈴臥推", sets: 3, reps: 10),
           let deadlift = makeTemplateExercise(name: "硬舉", sets: 3, reps: 8),
           let pullup = makeTemplateExercise(name: "引體向上", sets: 3, reps: 8),
           let shoulderPress = makeTemplateExercise(name: "肩推", sets: 3, reps: 10) {
            
            let fullBody = TemplateInfo(
                id: UUID(),
                name: "全身訓練",
                description: "適合初學者的全身訓練",
                exercises: [squat, benchPress, deadlift, pullup, shoulderPress],
                isSystem: true
            )
            _ = try repository.create(template: fullBody, userId: userId)
        }
        
        print("✅ 成功創建示例模板")
    }
    
    // MARK: - Development Helpers
    
    /// 重置所有數據（僅用於開發測試）
    func resetAllData() {
        #if DEBUG
        coreData.resetDatabase()
        UserDefaults.standard.removeObject(forKey: "DefaultDataInitialized")
        UserDefaults.standard.removeObject(forKey: "CoreDataMigrationCompleted")
        UserDefaults.standard.removeObject(forKey: "CurrentUserId")
        print("🗑️ 所有數據已重置")
        #endif
    }
    
    /// 打印數據庫統計
    func printDatabaseStats() {
        do {
            let workoutCount = try coreData.count(WorkoutEntity.self)
            let bodyWeightCount = try coreData.count(BodyWeightEntity.self)
            let exerciseCount = try coreData.count(ExerciseEntity.self)
            let templateCount = try coreData.count(TemplateEntity.self)
            let dbSize = coreData.getDatabaseSize()
            
            print("""
            
            📊 數據庫統計
            ────────────────────
            訓練記錄: \(workoutCount)
            體重記錄: \(bodyWeightCount)
            動作庫: \(exerciseCount)
            訓練模板: \(templateCount)
            數據庫大小: \(dbSize)
            ────────────────────
            
            """)
        } catch {
            print("❌ 無法獲取數據庫統計: \(error)")
        }
    }
}

// MARK: - Global Helper

extension DataMigrationService {
    /// 獲取當前用戶 ID
    static func getCurrentUserId() -> UUID {
        if let uuidString = UserDefaults.standard.string(forKey: "CurrentUserId"),
           let uuid = UUID(uuidString: uuidString) {
            return uuid
        }
        // 如果沒有，創建一個新的
        let newId = UUID()
        UserDefaults.standard.set(newId.uuidString, forKey: "CurrentUserId")
        return newId
    }
}

