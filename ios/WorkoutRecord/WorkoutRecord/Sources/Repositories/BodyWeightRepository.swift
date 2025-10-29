import Foundation
import CoreData

/// 體重記錄數據訪問層
class BodyWeightRepository {
    
    private let coreData = CoreDataStack.shared
    
    // MARK: - Create
    
    func create(bodyWeight: BodyWeight) throws -> BodyWeightEntity {
        let context = coreData.viewContext
        let entity = BodyWeightEntity(context: context)
        
        entity.id = bodyWeight.id
        entity.userId = bodyWeight.userId
        entity.weight = bodyWeight.weight
        entity.measuredAt = bodyWeight.measuredAt
        entity.note = bodyWeight.note
        entity.createdAt = bodyWeight.createdAt
        entity.updatedAt = bodyWeight.updatedAt
        entity.isSynced = false
        
        try coreData.save(context: context)
        return entity
    }
    
    // MARK: - Read
    
    func fetchAll() throws -> [BodyWeight] {
        let entities = try coreData.fetch(
            BodyWeightEntity.self,
            sortDescriptors: [NSSortDescriptor(key: "measuredAt", ascending: false)]
        )
        return entities.compactMap { convertToModel($0) }
    }
    
    func fetchByDateRange(from startDate: Date, to endDate: Date) throws -> [BodyWeight] {
        let predicate = NSPredicate(
            format: "measuredAt >= %@ AND measuredAt <= %@",
            startDate as NSDate,
            endDate as NSDate
        )
        let entities = try coreData.fetch(
            BodyWeightEntity.self,
            predicate: predicate,
            sortDescriptors: [NSSortDescriptor(key: "measuredAt", ascending: true)]
        )
        return entities.compactMap { convertToModel($0) }
    }
    
    func fetchRecent(limit: Int) throws -> [BodyWeight] {
        let entities = try coreData.fetch(
            BodyWeightEntity.self,
            sortDescriptors: [NSSortDescriptor(key: "measuredAt", ascending: false)],
            limit: limit
        )
        return entities.compactMap { convertToModel($0) }
    }
    
    // MARK: - Update
    
    func update(bodyWeight: BodyWeight) throws {
        let context = coreData.viewContext
        let predicate = NSPredicate(format: "id == %@", bodyWeight.id as CVarArg)
        let entities = try coreData.fetch(
            BodyWeightEntity.self,
            predicate: predicate,
            limit: 1
        )
        
        guard let entity = entities.first else {
            throw NSError(domain: "BodyWeightRepository", code: 404)
        }
        
        entity.weight = bodyWeight.weight
        entity.measuredAt = bodyWeight.measuredAt
        entity.note = bodyWeight.note
        entity.updatedAt = Date()
        entity.isSynced = false
        
        try coreData.save(context: context)
    }
    
    // MARK: - Delete
    
    func delete(id: UUID) throws {
        let context = coreData.viewContext
        let predicate = NSPredicate(format: "id == %@", id as CVarArg)
        let entities = try coreData.fetch(
            BodyWeightEntity.self,
            predicate: predicate,
            limit: 1
        )
        
        if let entity = entities.first {
            context.delete(entity)
            try coreData.save(context: context)
        }
    }
    
    // MARK: - Statistics
    
    func getLatestWeight() throws -> BodyWeight? {
        let entities = try coreData.fetch(
            BodyWeightEntity.self,
            sortDescriptors: [NSSortDescriptor(key: "measuredAt", ascending: false)],
            limit: 1
        )
        return entities.first.flatMap { convertToModel($0) }
    }
    
    func getAverageWeight(from startDate: Date, to endDate: Date) throws -> Double? {
        let weights = try fetchByDateRange(from: startDate, to: endDate)
        guard !weights.isEmpty else { return nil }
        return weights.reduce(0) { $0 + $1.weight } / Double(weights.count)
    }
    
    // MARK: - Conversion
    
    private func convertToModel(_ entity: BodyWeightEntity) -> BodyWeight? {
        return BodyWeight(
            id: entity.id ?? UUID(),
            userId: entity.userId ?? UUID(),
            weight: entity.weight,
            measuredAt: entity.measuredAt ?? Date(),
            note: entity.note,
            createdAt: entity.createdAt ?? Date(),
            updatedAt: entity.updatedAt ?? Date()
        )
    }
}

