import Foundation
import CoreData

class PersonalRecordRepository {
    private let coreDataStack = CoreDataStack.shared
    
    // MARK: - Create
    
    func create(personalRecord: PersonalRecord) throws -> PersonalRecord {
        let context = coreDataStack.viewContext
        let entity = PersonalRecordEntity(context: context)
        
        entity.id = personalRecord.id
        entity.userId = personalRecord.userId
        entity.exerciseId = personalRecord.exerciseId
        entity.weight = personalRecord.weight
        entity.reps = Int32(personalRecord.reps)
        entity.oneRepMax = personalRecord.oneRepMax
        entity.achievedAt = personalRecord.achievedAt
        entity.workoutId = personalRecord.workoutId
        entity.createdAt = personalRecord.createdAt
        entity.updatedAt = personalRecord.updatedAt
        
        try coreDataStack.save(context: context)
        
        print("✅ PersonalRecord 創建成功: \(personalRecord.id)")
        return personalRecord
    }
    
    // MARK: - Fetch
    
    func fetchById(_ id: UUID) throws -> PersonalRecord? {
        let predicate = NSPredicate(format: "id == %@", id as CVarArg)
        let entities = try coreDataStack.fetch(
            PersonalRecordEntity.self,
            predicate: predicate,
            limit: 1
        )
        
        return entities.first.flatMap { convertToModel($0) }
    }
    
    func fetchByExercise(_ exerciseId: UUID) throws -> [PersonalRecord] {
        let predicate = NSPredicate(format: "exerciseId == %@", exerciseId as CVarArg)
        let sortDescriptors = [NSSortDescriptor(key: "achievedAt", ascending: false)]
        
        let entities = try coreDataStack.fetch(
            PersonalRecordEntity.self,
            predicate: predicate,
            sortDescriptors: sortDescriptors
        )
        
        return entities.compactMap { convertToModel($0) }
    }
    
    func fetchByUser(_ userId: UUID) throws -> [PersonalRecord] {
        let predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        let sortDescriptors = [NSSortDescriptor(key: "achievedAt", ascending: false)]
        
        let entities = try coreDataStack.fetch(
            PersonalRecordEntity.self,
            predicate: predicate,
            sortDescriptors: sortDescriptors
        )
        
        return entities.compactMap { convertToModel($0) }
    }
    
    func fetchAll() throws -> [PersonalRecord] {
        let sortDescriptors = [NSSortDescriptor(key: "achievedAt", ascending: false)]
        
        let entities = try coreDataStack.fetch(
            PersonalRecordEntity.self,
            sortDescriptors: sortDescriptors
        )
        
        return entities.compactMap { convertToModel($0) }
    }
    
    /// 獲取所有個人記錄 (別名方法)
    func getAllPersonalRecords() throws -> [PersonalRecord] {
        return try fetchAll()
    }
    
    /// 根據 ID 獲取個人記錄 (別名方法)
    func getPersonalRecord(by id: UUID) throws -> PersonalRecord? {
        return try fetchById(id)
    }
    
    // MARK: - Get Current PR
    
    /// 獲取特定動作的當前 PR（最高 1RM）
    func getCurrentPR(exerciseId: UUID) throws -> PersonalRecord? {
        let predicate = NSPredicate(format: "exerciseId == %@", exerciseId as CVarArg)
        let sortDescriptors = [NSSortDescriptor(key: "oneRepMax", ascending: false)]
        
        let entities = try coreDataStack.fetch(
            PersonalRecordEntity.self,
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            limit: 1
        )
        
        return entities.first.flatMap { convertToModel($0) }
    }
    
    // MARK: - Get PR Summary
    
    /// 獲取用戶所有動作的 PR 總結（按肌群分組）
    func getPRSummary(userId: UUID) throws -> [PRSummary] {
        let exerciseRepo = ExerciseRepository()
        let allPRs = try fetchByUser(userId)
        
        // 按動作分組
        var prByExercise: [UUID: [PersonalRecord]] = [:]
        for pr in allPRs {
            prByExercise[pr.exerciseId, default: []].append(pr)
        }
        
        // 創建 Summary
        var summaries: [PRSummary] = []
        for (exerciseId, prs) in prByExercise {
            guard let exercise = try? exerciseRepo.fetchById(exerciseId) else {
                continue
            }
            
            // 找出最高 1RM 的 PR
            let currentPR = prs.max(by: { $0.oneRepMax < $1.oneRepMax })
            
            // PR 歷史（按日期排序）
            let history = prs.sorted(by: { $0.achievedAt > $1.achievedAt })
            
            let summary = PRSummary(
                exerciseId: exerciseId,
                exerciseName: exercise.name,
                primaryMuscleGroup: exercise.primaryMuscleGroup,
                currentPR: currentPR,
                prHistory: history
            )
            summaries.append(summary)
        }
        
        // 按肌群和動作名稱排序
        return summaries.sorted { s1, s2 in
            if s1.primaryMuscleGroup != s2.primaryMuscleGroup {
                let group1 = s1.primaryMuscleGroup?.rawValue ?? ""
                let group2 = s2.primaryMuscleGroup?.rawValue ?? ""
                return group1 < group2
            }
            return s1.exerciseName < s2.exerciseName
        }
    }
    
    // MARK: - Update
    
    func update(personalRecord: PersonalRecord) throws {
        let predicate = NSPredicate(format: "id == %@", personalRecord.id as CVarArg)
        let entities = try coreDataStack.fetch(
            PersonalRecordEntity.self,
            predicate: predicate,
            limit: 1
        )
        
        guard let entity = entities.first else {
            throw NSError(
                domain: "PersonalRecordRepository",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "PersonalRecord not found"]
            )
        }
        
        entity.weight = personalRecord.weight
        entity.reps = Int32(personalRecord.reps)
        entity.oneRepMax = personalRecord.oneRepMax
        entity.achievedAt = personalRecord.achievedAt
        entity.workoutId = personalRecord.workoutId
        entity.updatedAt = Date()
        
        try coreDataStack.save(context: coreDataStack.viewContext)
        print("✅ PersonalRecord 更新成功: \(personalRecord.id)")
    }
    
    // MARK: - Delete
    
    func delete(id: UUID) throws {
        let predicate = NSPredicate(format: "id == %@", id as CVarArg)
        let entities = try coreDataStack.fetch(
            PersonalRecordEntity.self,
            predicate: predicate,
            limit: 1
        )
        
        guard let entity = entities.first else {
            throw NSError(
                domain: "PersonalRecordRepository",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "PersonalRecord not found"]
            )
        }
        
        coreDataStack.viewContext.delete(entity)
        try coreDataStack.save(context: coreDataStack.viewContext)
        
        print("✅ PersonalRecord 刪除成功: \(id)")
    }
    
    func deleteByExercise(_ exerciseId: UUID) throws {
        let predicate = NSPredicate(format: "exerciseId == %@", exerciseId as CVarArg)
        let entities = try coreDataStack.fetch(
            PersonalRecordEntity.self,
            predicate: predicate
        )
        
        for entity in entities {
            coreDataStack.viewContext.delete(entity)
        }
        
        try coreDataStack.save(context: coreDataStack.viewContext)
        print("✅ 動作 \(exerciseId) 的所有 PR 已刪除")
    }
    
    // MARK: - Check for New PR
    
    /// 檢查是否為新 PR（根據 1RM）
    func isNewPR(exerciseId: UUID, oneRepMax: Double) throws -> Bool {
        guard let currentPR = try getCurrentPR(exerciseId: exerciseId) else {
            // 沒有現有 PR，這是第一次
            return true
        }
        
        return oneRepMax > currentPR.oneRepMax
    }
    
    // MARK: - Conversion
    
    private func convertToModel(_ entity: PersonalRecordEntity) -> PersonalRecord? {
        guard let id = entity.id,
              let userId = entity.userId,
              let exerciseId = entity.exerciseId,
              let achievedAt = entity.achievedAt,
              let createdAt = entity.createdAt,
              let updatedAt = entity.updatedAt else {
            return nil
        }
        
        return PersonalRecord(
            id: id,
            userId: userId,
            exerciseId: exerciseId,
            weight: entity.weight,
            reps: Int(entity.reps),
            oneRepMax: entity.oneRepMax,
            achievedAt: achievedAt,
            workoutId: entity.workoutId,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

