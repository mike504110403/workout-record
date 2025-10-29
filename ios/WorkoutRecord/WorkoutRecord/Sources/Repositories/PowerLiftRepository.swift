import Foundation
import CoreData

/// 三項記錄 Repository
class PowerLiftRepository {
    private let context = CoreDataStack.shared.viewContext
    
    // MARK: - Create
    
    /// 創建三項記錄
    func create(record: PowerLiftRecord) throws -> PowerLiftRecord {
        let entity = PowerLiftRecordEntity(context: context)
        entity.id = record.id
        entity.userId = record.userId
        entity.lift = record.lift.rawValue
        entity.weight = record.weight
        entity.reps = Int32(record.reps)
        entity.oneRepMax = record.oneRepMax
        entity.achievedAt = record.achievedAt
        entity.note = record.note
        entity.createdAt = record.createdAt
        entity.updatedAt = record.updatedAt
        
        try context.save()
        print("✅ 三項記錄已保存: \(record.lift.rawValue) \(record.weight)kg × \(record.reps) (1RM: \(record.oneRepMax)kg)")
        
        return record
    }
    
    // MARK: - Read
    
    /// 獲取指定用戶的所有三項記錄
    func getAll(userId: UUID) throws -> [PowerLiftRecord] {
        let request = PowerLiftRecordEntity.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "achievedAt", ascending: false)]
        
        let entities = try context.fetch(request)
        return entities.compactMap { entity in
            mapEntityToModel(entity)
        }
    }
    
    /// 獲取指定三項動作的所有記錄
    func getRecords(forLift lift: PowerLift, userId: UUID) throws -> [PowerLiftRecord] {
        let request = PowerLiftRecordEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "userId == %@ AND lift == %@",
            userId as CVarArg,
            lift.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(key: "achievedAt", ascending: false)]
        
        let entities = try context.fetch(request)
        return entities.compactMap { entity in
            mapEntityToModel(entity)
        }
    }
    
    /// 獲取指定三項動作的最佳記錄
    func getBestRecord(forLift lift: PowerLift, userId: UUID) throws -> PowerLiftRecord? {
        let request = PowerLiftRecordEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "userId == %@ AND lift == %@",
            userId as CVarArg,
            lift.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(key: "oneRepMax", ascending: false)]
        request.fetchLimit = 1
        
        guard let entity = try context.fetch(request).first else {
            return nil
        }
        
        return mapEntityToModel(entity)
    }
    
    /// 根據 ID 獲取記錄
    func getById(id: UUID) throws -> PowerLiftRecord? {
        let request = PowerLiftRecordEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        
        guard let entity = try context.fetch(request).first else {
            return nil
        }
        
        return mapEntityToModel(entity)
    }
    
    // MARK: - Update
    
    /// 更新三項記錄
    func update(record: PowerLiftRecord) throws -> PowerLiftRecord {
        let request = PowerLiftRecordEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", record.id as CVarArg)
        request.fetchLimit = 1
        
        guard let entity = try context.fetch(request).first else {
            throw NSError(domain: "PowerLiftRepository", code: 404, userInfo: [NSLocalizedDescriptionKey: "記錄不存在"])
        }
        
        entity.weight = record.weight
        entity.reps = Int32(record.reps)
        entity.oneRepMax = record.oneRepMax
        entity.achievedAt = record.achievedAt
        entity.note = record.note
        entity.updatedAt = Date()
        
        try context.save()
        print("✅ 三項記錄已更新: \(record.lift.rawValue) \(record.weight)kg")
        
        return record
    }
    
    // MARK: - Delete
    
    /// 刪除三項記錄
    func delete(id: UUID) throws {
        let request = PowerLiftRecordEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        
        guard let entity = try context.fetch(request).first else {
            throw NSError(domain: "PowerLiftRepository", code: 404, userInfo: [NSLocalizedDescriptionKey: "記錄不存在"])
        }
        
        context.delete(entity)
        try context.save()
        print("✅ 三項記錄已刪除")
    }
    
    /// 刪除指定用戶的所有記錄
    func deleteAll(userId: UUID) throws {
        let request = PowerLiftRecordEntity.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        
        let entities = try context.fetch(request)
        for entity in entities {
            context.delete(entity)
        }
        
        try context.save()
        print("✅ 已刪除所有三項記錄")
    }
    
    // MARK: - Helper Methods
    
    /// 將 Entity 轉換為 Model
    private func mapEntityToModel(_ entity: PowerLiftRecordEntity) -> PowerLiftRecord? {
        guard let liftString = entity.lift,
              let lift = PowerLift(rawValue: liftString),
              let achievedAt = entity.achievedAt,
              let createdAt = entity.createdAt,
              let updatedAt = entity.updatedAt,
              let userId = entity.userId else {
            return nil
        }
        
        return PowerLiftRecord(
            id: entity.id ?? UUID(),
            userId: userId,
            lift: lift,
            weight: entity.weight,
            reps: Int(entity.reps),
            oneRepMax: entity.oneRepMax,
            achievedAt: achievedAt,
            note: entity.note,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

