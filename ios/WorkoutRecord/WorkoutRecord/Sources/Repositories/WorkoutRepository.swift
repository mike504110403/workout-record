import Foundation
import CoreData

/// 訓練記錄數據訪問層
/// 封裝所有與 Workout 相關的數據庫操作
class WorkoutRepository {
    
    private let coreData = CoreDataStack.shared
    
    // MARK: - Create
    
    /// 創建新的訓練記錄
    func create(workout: Workout) throws -> WorkoutEntity {
        let context = coreData.viewContext
        let entity = WorkoutEntity(context: context)
        
        // 基本屬性
        entity.id = workout.id
        entity.userId = workout.userId
        entity.startedAt = workout.startedAt
        entity.endedAt = workout.endedAt
        entity.duration = Int32(workout.duration ?? 0)
        entity.totalVolume = workout.totalVolume
        entity.totalSets = Int32(workout.totalSets)
        entity.totalExercises = Int32(workout.totalExercises)
        entity.note = workout.note
        entity.templateId = workout.templateId
        entity.createdAt = workout.createdAt
        entity.updatedAt = workout.updatedAt
        entity.isSynced = false
        
        // 創建關聯的動作
        for workoutExercise in workout.exercises {
            let exerciseEntity = WorkoutExerciseEntity(context: context)
            exerciseEntity.id = workoutExercise.id
            exerciseEntity.workoutId = workout.id
            exerciseEntity.exerciseId = workoutExercise.exerciseId
            exerciseEntity.exerciseName = workoutExercise.exerciseName
            exerciseEntity.isCompleted = workoutExercise.isCompleted
            exerciseEntity.isCustomExercise = workoutExercise.isCustomExercise
            exerciseEntity.orderIndex = Int32(workoutExercise.orderIndex)
            exerciseEntity.totalVolume = workoutExercise.totalVolume
            exerciseEntity.totalSets = Int32(workoutExercise.totalSets)
            exerciseEntity.note = workoutExercise.note
            exerciseEntity.createdAt = workoutExercise.createdAt
            exerciseEntity.updatedAt = workoutExercise.updatedAt
            exerciseEntity.workout = entity
            
            // 創建關聯的組數
            for set in workoutExercise.sets {
                let setEntity = WorkoutSetEntity(context: context)
                setEntity.id = set.id
                setEntity.workoutExerciseId = workoutExercise.id
                setEntity.setNumber = Int32(set.setNumber)
                setEntity.weight = set.weight
                setEntity.reps = Int32(set.reps)
                setEntity.volume = set.volume
                setEntity.rpe = set.rpe ?? 0
                setEntity.restSeconds = Int32(set.restSeconds ?? 0)
                setEntity.isWarmup = set.isWarmup
                setEntity.note = set.note
                setEntity.createdAt = set.createdAt
                setEntity.updatedAt = set.updatedAt
                setEntity.workoutExercise = exerciseEntity
            }
        }
        
        try coreData.save(context: context)
        return entity
    }
    
    // MARK: - Read
    
    /// 獲取所有訓練記錄
    func fetchAll() throws -> [Workout] {
        let entities = try coreData.fetch(
            WorkoutEntity.self,
            sortDescriptors: [NSSortDescriptor(key: "startedAt", ascending: false)]
        )
        return entities.compactMap { convertToModel($0) }
    }
    
    /// 獲取所有訓練記錄 (別名方法)
    func getAllWorkouts() throws -> [Workout] {
        return try fetchAll()
    }
    
    /// 根據 ID 獲取訓練
    func fetchById(_ id: UUID) throws -> Workout? {
        let predicate = NSPredicate(format: "id == %@", id as CVarArg)
        let entities = try coreData.fetch(
            WorkoutEntity.self,
            predicate: predicate,
            limit: 1
        )
        return entities.first.flatMap { convertToModel($0) }
    }
    
    /// 根據 ID 獲取訓練 (別名方法)
    func getWorkout(by id: UUID) throws -> Workout? {
        return try fetchById(id)
    }
    
    /// 獲取指定時間範圍的訓練
    func fetchByDateRange(from startDate: Date, to endDate: Date) throws -> [Workout] {
        let predicate = NSPredicate(
            format: "startedAt >= %@ AND startedAt <= %@",
            startDate as NSDate,
            endDate as NSDate
        )
        let entities = try coreData.fetch(
            WorkoutEntity.self,
            predicate: predicate,
            sortDescriptors: [NSSortDescriptor(key: "startedAt", ascending: false)]
        )
        return entities.compactMap { convertToModel($0) }
    }
    
    /// 獲取最近 N 次訓練
    func fetchRecent(limit: Int) throws -> [Workout] {
        let entities = try coreData.fetch(
            WorkoutEntity.self,
            sortDescriptors: [NSSortDescriptor(key: "startedAt", ascending: false)],
            limit: limit
        )
        return entities.compactMap { convertToModel($0) }
    }
    
    // MARK: - Update
    
    /// 更新訓練記錄
    func update(workout: Workout) throws {
        let context = coreData.viewContext
        let predicate = NSPredicate(format: "id == %@", workout.id as CVarArg)
        let entities = try coreData.fetch(
            WorkoutEntity.self,
            predicate: predicate,
            limit: 1
        )
        
        guard let entity = entities.first else {
            throw NSError(domain: "WorkoutRepository", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Workout not found"
            ])
        }
        
        // 更新基本屬性
        entity.endedAt = workout.endedAt
        entity.duration = Int32(workout.duration ?? 0)
        entity.totalVolume = workout.totalVolume
        entity.totalSets = Int32(workout.totalSets)
        entity.totalExercises = Int32(workout.totalExercises)
        entity.note = workout.note
        entity.updatedAt = Date()
        entity.isSynced = false
        
        try coreData.save(context: context)
    }
    
    // MARK: - Delete
    
    /// 刪除訓練記錄
    func delete(id: UUID) throws {
        let context = coreData.viewContext
        let predicate = NSPredicate(format: "id == %@", id as CVarArg)
        let entities = try coreData.fetch(
            WorkoutEntity.self,
            predicate: predicate,
            limit: 1
        )
        
        if let entity = entities.first {
            context.delete(entity)
            try coreData.save(context: context)
        }
    }
    
    /// 批量刪除舊訓練（清理數據）
    func deleteOlderThan(date: Date) throws {
        let predicate = NSPredicate(format: "startedAt < %@", date as NSDate)
        try coreData.batchDelete(WorkoutEntity.self, predicate: predicate)
    }
    
    // MARK: - Statistics
    
    /// 計算總容量（指定時間範圍）
    func calculateTotalVolume(from startDate: Date? = nil, to endDate: Date? = nil) throws -> Double {
        var predicateFormat = "1 == 1"
        var arguments: [Any] = []
        
        if let start = startDate {
            predicateFormat += " AND startedAt >= %@"
            arguments.append(start as NSDate)
        }
        if let end = endDate {
            predicateFormat += " AND startedAt <= %@"
            arguments.append(end as NSDate)
        }
        
        let predicate = NSPredicate(format: predicateFormat, argumentArray: arguments)
        let fetchRequest: NSFetchRequest<NSDictionary> = NSFetchRequest(entityName: "WorkoutEntity")
        fetchRequest.predicate = predicate
        fetchRequest.resultType = .dictionaryResultType
        
        let sumExpression = NSExpression(forFunction: "sum:", arguments: [
            NSExpression(forKeyPath: "totalVolume")
        ])
        let description = NSExpressionDescription()
        description.name = "sum"
        description.expression = sumExpression
        description.expressionResultType = .doubleAttributeType
        
        fetchRequest.propertiesToFetch = [description]
        
        let result = try coreData.viewContext.fetch(fetchRequest)
        return result.first?["sum"] as? Double ?? 0
    }
    
    /// 計算訓練次數
    func countWorkouts(from startDate: Date? = nil, to endDate: Date? = nil) throws -> Int {
        var predicateFormat = "1 == 1"
        var arguments: [Any] = []
        
        if let start = startDate {
            predicateFormat += " AND startedAt >= %@"
            arguments.append(start as NSDate)
        }
        if let end = endDate {
            predicateFormat += " AND startedAt <= %@"
            arguments.append(end as NSDate)
        }
        
        let predicate = NSPredicate(format: predicateFormat, argumentArray: arguments)
        return try coreData.count(WorkoutEntity.self, predicate: predicate)
    }
    
    // MARK: - Conversion
    
    /// 將 Entity 轉換為 Model
    private func convertToModel(_ entity: WorkoutEntity) -> Workout? {
        let exerciseRepo = ExerciseRepository()
        
        // 轉換 WorkoutExercise
        let exercises = (entity.exercises?.array as? [WorkoutExerciseEntity])?.compactMap { exerciseEntity -> WorkoutExercise in
            // 轉換 WorkoutSet
            let sets = (exerciseEntity.sets?.array as? [WorkoutSetEntity])?.map { setEntity -> WorkoutSet in
                return WorkoutSet(
                    id: setEntity.id ?? UUID(),
                    workoutExerciseId: setEntity.workoutExerciseId ?? UUID(),
                    setNumber: Int(setEntity.setNumber),
                    weight: setEntity.weight,
                    reps: Int(setEntity.reps),
                    rpe: setEntity.rpe > 0 ? setEntity.rpe : nil,
                    restSeconds: setEntity.restSeconds > 0 ? Int(setEntity.restSeconds) : nil,
                    isWarmup: setEntity.isWarmup,
                    note: setEntity.note,
                    createdAt: setEntity.createdAt ?? Date(),
                    updatedAt: setEntity.updatedAt ?? Date()
                )
            } ?? []
            
            // ✅ 加載 exercise 數據以獲取肌群信息
            let exerciseId = exerciseEntity.exerciseId ?? UUID()
            let exercise = try? exerciseRepo.fetchById(exerciseId)
            
            // 調試日誌
            if exercise == nil {
                print("⚠️ 無法載入動作: exerciseId=\(exerciseId)")
            } else if let ex = exercise {
                print("✅ 載入動作: \(ex.name), primaryMuscleGroup=\(ex.primaryMuscleGroup?.displayName ?? "nil")")
            }
            
            return WorkoutExercise(
                id: exerciseEntity.id ?? UUID(),
                workoutId: exerciseEntity.workoutId ?? UUID(),
                exerciseId: exerciseId,
                exercise: exercise, // ✅ 加載完整的 exercise 對象
                exerciseName: exerciseEntity.exerciseName, // ✅ 載入備用動作名稱
                orderIndex: Int(exerciseEntity.orderIndex),
                totalVolume: exerciseEntity.totalVolume,
                totalSets: Int(exerciseEntity.totalSets),
                note: exerciseEntity.note,
                sets: sets,
                isCustomExercise: exerciseEntity.isCustomExercise,
                isCompleted: exerciseEntity.isCompleted,
                createdAt: exerciseEntity.createdAt ?? Date(),
                updatedAt: exerciseEntity.updatedAt ?? Date()
            )
        } ?? []
        
        return Workout(
            id: entity.id ?? UUID(),
            userId: entity.userId ?? UUID(),
            startedAt: entity.startedAt ?? Date(),
            endedAt: entity.endedAt,
            duration: entity.duration > 0 ? Int(entity.duration) : nil,
            totalVolume: entity.totalVolume,
            totalSets: Int(entity.totalSets),
            totalExercises: Int(entity.totalExercises),
            note: entity.note,
            templateId: entity.templateId,
            exercises: exercises,
            createdAt: entity.createdAt ?? Date(),
            updatedAt: entity.updatedAt ?? Date()
        )
    }
}

