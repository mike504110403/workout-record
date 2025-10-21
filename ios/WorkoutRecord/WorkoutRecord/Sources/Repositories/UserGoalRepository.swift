import Foundation
import CoreData

class UserGoalRepository {
    private let coreDataStack = CoreDataStack.shared
    
    // MARK: - Create or Update
    
    /// 創建或更新用戶目標（每個用戶只有一個目標記錄）
    func createOrUpdate(userGoal: UserGoal) throws -> UserGoal {
        let context = coreDataStack.viewContext
        
        // 嘗試查找現有記錄
        let predicate = NSPredicate(format: "userId == %@", userGoal.userId as CVarArg)
        let existingEntities = try coreDataStack.fetch(
            UserGoalEntity.self,
            predicate: predicate,
            limit: 1
        )
        
        let entity: UserGoalEntity
        if let existing = existingEntities.first {
            // 更新現有記錄
            entity = existing
        } else {
            // 創建新記錄
            entity = UserGoalEntity(context: context)
            entity.id = userGoal.id
            entity.userId = userGoal.userId
            entity.createdAt = userGoal.createdAt
        }
        
        // 更新屬性
        entity.weeklyWorkoutGoal = Int32(userGoal.weeklyWorkoutGoal)
        entity.targetWeight = userGoal.targetWeight ?? 0
        entity.chestVolumeGoal = userGoal.volumeGoals.chest ?? 0
        entity.backVolumeGoal = userGoal.volumeGoals.back ?? 0
        entity.legsVolumeGoal = userGoal.volumeGoals.legs ?? 0
        entity.shouldersVolumeGoal = userGoal.volumeGoals.shoulders ?? 0
        entity.armsVolumeGoal = userGoal.volumeGoals.arms ?? 0
        entity.coreVolumeGoal = userGoal.volumeGoals.core ?? 0
        entity.restDayReminder = userGoal.restDayReminder
        entity.updatedAt = Date()
        
        try coreDataStack.save(context: context)
        
        print("✅ UserGoal 保存成功")
        return userGoal
    }
    
    // MARK: - Fetch
    
    func fetchByUser(_ userId: UUID) throws -> UserGoal? {
        let predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        
        do {
            let entities = try coreDataStack.fetch(
                UserGoalEntity.self,
                predicate: predicate,
                limit: 1
            )
            
            return entities.first.flatMap { convertToModel($0) }
        } catch {
            // 如果是首次運行，entity 可能還不存在，這是正常的
            print("⚠️ UserGoalRepository.fetchByUser 錯誤: \(error)")
            return nil
        }
    }
    
    // MARK: - Delete
    
    func delete(userId: UUID) throws {
        let predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        let entities = try coreDataStack.fetch(
            UserGoalEntity.self,
            predicate: predicate
        )
        
        for entity in entities {
            coreDataStack.viewContext.delete(entity)
        }
        
        try coreDataStack.save(context: coreDataStack.viewContext)
        print("✅ UserGoal 刪除成功")
    }
    
    // MARK: - Conversion
    
    private func convertToModel(_ entity: UserGoalEntity) -> UserGoal? {
        guard let id = entity.id,
              let userId = entity.userId,
              let createdAt = entity.createdAt,
              let updatedAt = entity.updatedAt else {
            return nil
        }
        
        let volumeGoals = VolumeGoals(
            chest: entity.chestVolumeGoal > 0 ? entity.chestVolumeGoal : nil,
            back: entity.backVolumeGoal > 0 ? entity.backVolumeGoal : nil,
            legs: entity.legsVolumeGoal > 0 ? entity.legsVolumeGoal : nil,
            shoulders: entity.shouldersVolumeGoal > 0 ? entity.shouldersVolumeGoal : nil,
            arms: entity.armsVolumeGoal > 0 ? entity.armsVolumeGoal : nil,
            core: entity.coreVolumeGoal > 0 ? entity.coreVolumeGoal : nil
        )
        
        return UserGoal(
            id: id,
            userId: userId,
            weeklyWorkoutGoal: Int(entity.weeklyWorkoutGoal),
            targetWeight: entity.targetWeight > 0 ? entity.targetWeight : nil,
            volumeGoals: volumeGoals,
            restDayReminder: entity.restDayReminder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

