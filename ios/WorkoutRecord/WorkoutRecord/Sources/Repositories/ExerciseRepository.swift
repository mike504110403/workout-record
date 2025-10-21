import Foundation
import CoreData

/// 動作庫數據訪問層
class ExerciseRepository {
    
    private let coreData = CoreDataStack.shared
    
    // MARK: - Create
    
    func create(exercise: Exercise) throws -> ExerciseEntity {
        let context = coreData.viewContext
        let entity = ExerciseEntity(context: context)
        
        entity.id = exercise.id
        entity.name = exercise.name
        entity.nameEn = exercise.nameEn
        entity.categoryId = exercise.categoryId
        entity.type = exercise.type.rawValue
        entity.primaryMuscleGroup = exercise.primaryMuscleGroup?.rawValue
        entity.movementPattern = exercise.movementPattern?.rawValue
        entity.descriptionText = exercise.description
        entity.imageURL = exercise.imageURL
        entity.videoURL = exercise.videoURL
        entity.isSystem = exercise.isSystem
        entity.isActive = true
        entity.userId = exercise.userId
        entity.createdAt = exercise.createdAt
        entity.updatedAt = exercise.updatedAt
        
        try coreData.save(context: context)
        return entity
    }
    
    /// 批量創建（用於初始化系統動作）
    func batchCreate(exercises: [Exercise]) throws {
        let context = coreData.newBackgroundContext()
        
        for exercise in exercises {
            let entity = ExerciseEntity(context: context)
            entity.id = exercise.id
            entity.name = exercise.name
            entity.nameEn = exercise.nameEn
            entity.categoryId = exercise.categoryId
            entity.type = exercise.type.rawValue
            entity.primaryMuscleGroup = exercise.primaryMuscleGroup?.rawValue
            entity.movementPattern = exercise.movementPattern?.rawValue
            entity.descriptionText = exercise.description
            entity.imageURL = exercise.imageURL
            entity.videoURL = exercise.videoURL
            entity.isSystem = exercise.isSystem
            entity.isActive = true
            entity.userId = exercise.userId
            entity.createdAt = exercise.createdAt
            entity.updatedAt = exercise.updatedAt
        }
        
        try coreData.save(context: context)
    }
    
    // MARK: - Read
    
    func fetchAll(includeInactive: Bool = false) throws -> [Exercise] {
        var predicate: NSPredicate?
        if !includeInactive {
            predicate = NSPredicate(format: "isActive == YES")
        }
        
        let entities = try coreData.fetch(
            ExerciseEntity.self,
            predicate: predicate,
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
        )
        return entities.compactMap { convertToModel($0) }
    }
    
    func fetchById(_ id: UUID) throws -> Exercise? {
        let predicate = NSPredicate(format: "id == %@", id as CVarArg)
        let entities = try coreData.fetch(
            ExerciseEntity.self,
            predicate: predicate,
            limit: 1
        )
        return entities.first.flatMap { convertToModel($0) }
    }
    
    func fetchByCategory(_ categoryId: UUID) throws -> [Exercise] {
        let predicate = NSPredicate(
            format: "categoryId == %@ AND isActive == YES",
            categoryId as CVarArg
        )
        let entities = try coreData.fetch(
            ExerciseEntity.self,
            predicate: predicate,
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
        )
        return entities.compactMap { convertToModel($0) }
    }
    
    func fetchByType(_ type: Exercise.ExerciseType) throws -> [Exercise] {
        let predicate = NSPredicate(
            format: "type == %@ AND isActive == YES",
            type.rawValue
        )
        let entities = try coreData.fetch(
            ExerciseEntity.self,
            predicate: predicate,
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
        )
        return entities.compactMap { convertToModel($0) }
    }
    
    func fetchSystemExercises() throws -> [Exercise] {
        let predicate = NSPredicate(format: "isSystem == YES AND isActive == YES")
        let entities = try coreData.fetch(
            ExerciseEntity.self,
            predicate: predicate,
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
        )
        return entities.compactMap { convertToModel($0) }
    }
    
    func fetchCustomExercises(userId: UUID) throws -> [Exercise] {
        let predicate = NSPredicate(
            format: "isSystem == NO AND userId == %@ AND isActive == YES",
            userId as CVarArg
        )
        let entities = try coreData.fetch(
            ExerciseEntity.self,
            predicate: predicate,
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
        )
        return entities.compactMap { convertToModel($0) }
    }
    
    /// 搜索動作
    func search(keyword: String) throws -> [Exercise] {
        let predicate = NSPredicate(
            format: "(name CONTAINS[cd] %@ OR nameEn CONTAINS[cd] %@) AND isActive == YES",
            keyword, keyword
        )
        let entities = try coreData.fetch(
            ExerciseEntity.self,
            predicate: predicate,
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
        )
        return entities.compactMap { convertToModel($0) }
    }
    
    // MARK: - Update
    
    func update(exercise: Exercise) throws {
        let context = coreData.viewContext
        let predicate = NSPredicate(format: "id == %@", exercise.id as CVarArg)
        let entities = try coreData.fetch(
            ExerciseEntity.self,
            predicate: predicate,
            limit: 1
        )
        
        guard let entity = entities.first else {
            throw NSError(domain: "ExerciseRepository", code: 404)
        }
        
        entity.name = exercise.name
        entity.nameEn = exercise.nameEn
        entity.categoryId = exercise.categoryId
        entity.type = exercise.type.rawValue
        entity.primaryMuscleGroup = exercise.primaryMuscleGroup?.rawValue
        entity.movementPattern = exercise.movementPattern?.rawValue
        entity.descriptionText = exercise.description
        entity.imageURL = exercise.imageURL
        entity.videoURL = exercise.videoURL
        entity.updatedAt = Date()
        
        try coreData.save(context: context)
    }
    
    // MARK: - Delete (Soft Delete)
    
    func delete(id: UUID) throws {
        let context = coreData.viewContext
        let predicate = NSPredicate(format: "id == %@", id as CVarArg)
        let entities = try coreData.fetch(
            ExerciseEntity.self,
            predicate: predicate,
            limit: 1
        )
        
        guard let entity = entities.first else { return }
        
        // 軟刪除：只標記為不活躍
        entity.isActive = false
        entity.updatedAt = Date()
        
        try coreData.save(context: context)
    }
    
    /// 永久刪除（僅用於自定義動作）
    func permanentDelete(id: UUID) throws {
        let context = coreData.viewContext
        let predicate = NSPredicate(
            format: "id == %@ AND isSystem == NO",
            id as CVarArg
        )
        let entities = try coreData.fetch(
            ExerciseEntity.self,
            predicate: predicate,
            limit: 1
        )
        
        if let entity = entities.first {
            context.delete(entity)
            try coreData.save(context: context)
        }
    }
    
    // MARK: - Conversion
    
    private func convertToModel(_ entity: ExerciseEntity) -> Exercise? {
        guard let id = entity.id,
              let name = entity.name,
              let typeRaw = entity.type,
              let type = Exercise.ExerciseType(rawValue: typeRaw),
              let categoryId = entity.categoryId else {
            return nil
        }
        
        return Exercise(
            id: id,
            name: name,
            nameEn: entity.nameEn,
            categoryId: categoryId,
            type: type,
            primaryMuscleGroup: entity.primaryMuscleGroup.flatMap { Exercise.PrimaryMuscleGroup(rawValue: $0) },
            movementPattern: entity.movementPattern.flatMap { Exercise.MovementPattern(rawValue: $0) },
            description: entity.descriptionText,
            videoURL: entity.videoURL,
            imageURL: entity.imageURL,
            isSystem: entity.isSystem,
            userId: entity.userId,
            createdAt: entity.createdAt ?? Date(),
            updatedAt: entity.updatedAt ?? Date()
        )
    }
}

