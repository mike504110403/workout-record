import Foundation
import CloudKit
import CoreData
import Combine

/// CloudKit 數據同步服務
class CloudKitSyncService: ObservableObject {
    static let shared = CloudKitSyncService()
    
    @Published var isSyncing = false
    @Published var syncProgress: Double = 0.0
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    
    private let container = CKContainer.default()
    private let privateDatabase: CKDatabase
    private let coreDataStack: CoreDataStack
    
    init() {
        self.privateDatabase = container.privateCloudDatabase
        self.coreDataStack = CoreDataStack.shared
    }
    
    // MARK: - 同步管理
    
    /// 開始完整同步
    func startFullSync() async {
        await MainActor.run {
            isSyncing = true
            syncProgress = 0.0
            syncError = nil
        }
        
        do {
            // 1. 同步用戶設定
            try await syncUserProfile()
            await updateProgress(0.2)
            
            // 2. 同步訓練記錄
            try await syncWorkouts()
            await updateProgress(0.6)
            
            // 3. 同步體重記錄
            try await syncBodyWeights()
            await updateProgress(0.8)
            
            // 4. 同步成就記錄
            try await syncAchievements()
            await updateProgress(1.0)
            
            await MainActor.run {
                lastSyncDate = Date()
                isSyncing = false
            }
            
        } catch {
            await MainActor.run {
                syncError = error.localizedDescription
                isSyncing = false
            }
        }
    }
    
    /// 增量同步
    func startIncrementalSync() async {
        guard let lastSync = lastSyncDate else {
            await startFullSync()
            return
        }
        
        await MainActor.run {
            isSyncing = true
            syncProgress = 0.0
        }
        
        do {
            // 只同步上次同步後的變更
            try await syncChangesSince(lastSync)
            
            await MainActor.run {
                lastSyncDate = Date()
                isSyncing = false
            }
            
        } catch {
            await MainActor.run {
                syncError = error.localizedDescription
                isSyncing = false
            }
        }
    }
    
    // MARK: - 用戶設定同步
    
    private func syncUserProfile() async throws {
        let profile = UserProfile.shared
        let record = CKRecord(recordType: "UserProfile")
        
        record["name"] = profile.name
        record["email"] = profile.email
        record["gender"] = profile.gender
        record["age"] = profile.age
        record["height"] = profile.height
        record["currentWeight"] = profile.currentWeight
        record["targetWeight"] = profile.targetWeight
        record["weeklyGoal"] = profile.weeklyGoal
        record["lastSyncDate"] = Date()
        
        try await privateDatabase.save(record)
    }
    
    // MARK: - 訓練記錄同步
    
    private func syncWorkouts() async throws {
        let workoutRepository = WorkoutRepository()
        let workouts = try workoutRepository.fetchAll()
        
        for workout in workouts {
            let record = CKRecord(recordType: "Workout", recordID: CKRecord.ID(recordName: workout.id.uuidString))
            
            record["startedAt"] = workout.startedAt
            record["endedAt"] = workout.endedAt
            record["totalVolume"] = workout.totalVolume
            record["note"] = workout.note ?? ""
            record["templateId"] = workout.templateId?.uuidString ?? ""
            
            // 同步訓練動作
            let exerciseRecords = try await syncWorkoutExercises(workout: workout)
            // 無法直接儲存 CKRecord.ID 陣列，改為儲存 UUID 字串陣列
            record["exerciseIds"] = exerciseRecords.map { $0.recordID.recordName }
            
            try await privateDatabase.save(record)
        }
    }
    
    private func syncWorkoutExercises(workout: Workout) async throws -> [CKRecord] {
        var exerciseRecords: [CKRecord] = []
        
        for exercise in workout.exercises {
            let record = CKRecord(recordType: "WorkoutExercise")
            
            record["exerciseName"] = exercise.exercise?.name ?? ""
            record["muscleGroups"] = exercise.exercise?.muscleGroups ?? []
            record["orderIndex"] = exercise.orderIndex
            
            // 同步組數
            let setRecords = try await syncWorkoutSets(exercise: exercise)
            record["setIds"] = setRecords.map { $0.recordID.recordName }
            
            exerciseRecords.append(record)
        }
        
        return exerciseRecords
    }
    
    private func syncWorkoutSets(exercise: WorkoutExercise) async throws -> [CKRecord] {
        var setRecords: [CKRecord] = []
        
        for set in exercise.sets {
            let record = CKRecord(recordType: "WorkoutSet")
            
            record["weight"] = set.weight
            record["reps"] = set.reps
            record["restSeconds"] = set.restSeconds ?? 0
            record["isWarmup"] = set.isWarmup
            record["setNumber"] = set.setNumber
            
            setRecords.append(record)
        }
        
        return setRecords
    }
    
    // MARK: - 體重記錄同步
    
    private func syncBodyWeights() async throws {
        let bodyWeightRepository = BodyWeightRepository()
        let bodyWeights = try bodyWeightRepository.fetchAll()
        
        for bodyWeight in bodyWeights {
            let record = CKRecord(recordType: "BodyWeight", recordID: CKRecord.ID(recordName: bodyWeight.id.uuidString))
            
            record["weight"] = bodyWeight.weight
            record["measuredAt"] = bodyWeight.measuredAt
            record["note"] = bodyWeight.note ?? ""
            record["createdAt"] = bodyWeight.createdAt
            record["updatedAt"] = bodyWeight.updatedAt
            
            try await privateDatabase.save(record)
        }
    }
    
    // MARK: - 成就記錄同步
    
    private func syncAchievements() async throws {
        // 同步成就解鎖狀態
        let achievements = Achievements.all
        
        for achievement in achievements {
            let record = CKRecord(recordType: "Achievement", recordID: CKRecord.ID(recordName: achievement.id))
            
            record["title"] = achievement.title
            record["description"] = achievement.description
            record["category"] = achievement.category.rawValue
            record["isUnlocked"] = achievement.isUnlocked
            record["unlockedAt"] = achievement.unlockedAt
            record["progress"] = achievement.progress
            
            try await privateDatabase.save(record)
        }
    }
    
    // MARK: - 變更同步
    
    private func syncChangesSince(_ date: Date) async throws {
        // 查詢自指定日期以來的變更
        let query = CKQuery(recordType: "Workout", predicate: NSPredicate(format: "modificationDate > %@", date as NSDate))
        let results = try await privateDatabase.records(matching: query)
        
        // 處理變更
        for (_, result) in results.matchResults {
            switch result {
            case .success(let record):
                try await processRecordChange(record)
            case .failure(let error):
                throw error
            }
        }
    }
    
    private func processRecordChange(_ record: CKRecord) async throws {
        // 根據記錄類型處理變更
        switch record.recordType {
        case "Workout":
            try await processWorkoutChange(record)
        case "BodyWeight":
            try await processBodyWeightChange(record)
        case "Achievement":
            try await processAchievementChange(record)
        default:
            break
        }
    }
    
    private func processWorkoutChange(_ record: CKRecord) async throws {
        // 處理訓練記錄變更
        // 這裡可以實作具體的變更處理邏輯
    }
    
    private func processBodyWeightChange(_ record: CKRecord) async throws {
        // 處理體重記錄變更
        // 這裡可以實作具體的變更處理邏輯
    }
    
    private func processAchievementChange(_ record: CKRecord) async throws {
        // 處理成就記錄變更
        // 這裡可以實作具體的變更處理邏輯
    }
    
    // MARK: - 進度更新
    
    private func updateProgress(_ progress: Double) async {
        await MainActor.run {
            syncProgress = progress
        }
    }
    
    // MARK: - 錯誤處理
    
    func clearSyncError() {
        syncError = nil
    }
}
