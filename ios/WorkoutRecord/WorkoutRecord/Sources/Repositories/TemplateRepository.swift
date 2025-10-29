import Foundation
import CoreData

/// 訓練模板數據訪問層
class TemplateRepository {
    
    private let coreData = CoreDataStack.shared
    
    // MARK: - Create
    
    func create(template: TemplateInfo, userId: UUID) throws -> TemplateEntity {
        let context = coreData.viewContext
        let entity = TemplateEntity(context: context)
        
        entity.id = template.id
        entity.userId = userId
        entity.name = template.name
        entity.descriptionText = template.description
        entity.isSystem = false
        entity.createdAt = Date()
        entity.updatedAt = Date()
        
        // 創建模板動作
        for (index, exercise) in template.exercises.enumerated() {
            let exerciseEntity = TemplateExerciseEntity(context: context)
            exerciseEntity.id = UUID()
            exerciseEntity.templateId = template.id
            exerciseEntity.exerciseId = exercise.id
            exerciseEntity.orderIndex = Int32(index)
            exerciseEntity.suggestedSets = exercise.suggestedSets.map { Int32($0) } ?? 0
            exerciseEntity.suggestedReps = exercise.suggestedReps.map { Int32($0) } ?? 0
            exerciseEntity.template = entity
        }
        
        try coreData.save(context: context)
        return entity
    }
    
    // MARK: - Read
    
    func fetchAll(userId: UUID) throws -> [TemplateInfo] {
        let predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        let entities = try coreData.fetch(
            TemplateEntity.self,
            predicate: predicate,
            sortDescriptors: [
                NSSortDescriptor(key: "isSystem", ascending: false),
                NSSortDescriptor(key: "name", ascending: true)
            ]
        )
        return entities.compactMap { convertToModel($0) }
    }
    
    func fetchById(_ id: UUID) throws -> TemplateInfo? {
        let predicate = NSPredicate(format: "id == %@", id as CVarArg)
        let entities = try coreData.fetch(
            TemplateEntity.self,
            predicate: predicate,
            limit: 1
        )
        return entities.first.flatMap { convertToModel($0) }
    }
    
    func fetchSystemTemplates() throws -> [TemplateInfo] {
        let predicate = NSPredicate(format: "isSystem == YES")
        let entities = try coreData.fetch(
            TemplateEntity.self,
            predicate: predicate,
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
        )
        return entities.compactMap { convertToModel($0) }
    }
    
    // MARK: - Update
    
    func update(template: TemplateInfo) throws {
        let context = coreData.viewContext
        let predicate = NSPredicate(format: "id == %@", template.id as CVarArg)
        let entities = try coreData.fetch(
            TemplateEntity.self,
            predicate: predicate,
            limit: 1
        )
        
        guard let entity = entities.first else {
            throw NSError(domain: "TemplateRepository", code: 404)
        }
        
        // 更新基本信息
        entity.name = template.name
        entity.descriptionText = template.description
        entity.updatedAt = Date()
        
        // 刪除舊的動作關聯
        if let oldExercises = entity.exercises?.array as? [TemplateExerciseEntity] {
            for exercise in oldExercises {
                context.delete(exercise)
            }
        }
        
        // 創建新的動作關聯
        for (index, exercise) in template.exercises.enumerated() {
            let exerciseEntity = TemplateExerciseEntity(context: context)
            exerciseEntity.id = UUID()
            exerciseEntity.templateId = template.id
            exerciseEntity.exerciseId = exercise.id
            exerciseEntity.orderIndex = Int32(index)
            exerciseEntity.suggestedSets = exercise.suggestedSets.map { Int32($0) } ?? 0
            exerciseEntity.suggestedReps = exercise.suggestedReps.map { Int32($0) } ?? 0
            exerciseEntity.template = entity
        }
        
        try coreData.save(context: context)
    }
    
    // MARK: - Delete
    
    func delete(id: UUID) throws {
        let context = coreData.viewContext
        let predicate = NSPredicate(
            format: "id == %@ AND isSystem == NO",
            id as CVarArg
        )
        let entities = try coreData.fetch(
            TemplateEntity.self,
            predicate: predicate,
            limit: 1
        )
        
        if let entity = entities.first {
            context.delete(entity)
            try coreData.save(context: context)
        }
    }
    
    // MARK: - Conversion
    
    private func convertToModel(_ entity: TemplateEntity) -> TemplateInfo? {
        guard let id = entity.id,
              let name = entity.name else {
            return nil
        }
        
        // 轉換動作列表
        let exerciseRepo = ExerciseRepository()
        let exercises = (entity.exercises?.array as? [TemplateExerciseEntity])?.compactMap { exerciseEntity -> TemplateInfo.TemplateExercise? in
            guard let exerciseId = exerciseEntity.exerciseId else {
                return nil
            }
            
            // 從 ExerciseRepository 獲取完整的 Exercise 信息
            guard let exercise = try? exerciseRepo.fetchById(exerciseId) else {
                // 如果找不到，創建一個占位符
                let placeholderExercise = Exercise(
                    id: exerciseId,
                    name: "Unknown Exercise",
                    categoryId: UUID(),
                    type: .freeWeight,
                    isSystem: true
                )
                return TemplateInfo.TemplateExercise(
                    id: exerciseId,
                    exercise: placeholderExercise,
                    suggestedSets: exerciseEntity.suggestedSets > 0 ? Int(exerciseEntity.suggestedSets) : nil,
                    suggestedReps: exerciseEntity.suggestedReps > 0 ? Int(exerciseEntity.suggestedReps) : nil
                )
            }
            
            return TemplateInfo.TemplateExercise(
                id: exerciseId,
                exercise: exercise,
                suggestedSets: exerciseEntity.suggestedSets > 0 ? Int(exerciseEntity.suggestedSets) : nil,
                suggestedReps: exerciseEntity.suggestedReps > 0 ? Int(exerciseEntity.suggestedReps) : nil
            )
        } ?? []
        
        return TemplateInfo(
            id: id,
            name: name,
            description: entity.descriptionText,
            exercises: exercises,
            isSystem: entity.isSystem
        )
    }
}

