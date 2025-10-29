import Foundation
import CloudKit
import Combine
import UIKit
import CoreData

/// iCloud 同步服務
@MainActor
class CloudKitSyncService: ObservableObject {
    static let shared = CloudKitSyncService()
    
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    @Published var syncProgress: Double = 0.0
    
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let publicDatabase: CKDatabase
    private var cancellables = Set<AnyCancellable>()
    
    // 同步狀態
    private var isInitialSync = true
    private var syncInProgress = false
    
    init() {
        self.container = CKContainer.default()
        self.privateDatabase = container.privateCloudDatabase
        self.publicDatabase = container.publicCloudDatabase
        
        setupSyncObservers()
    }
    
    // MARK: - Setup
    
    private func setupSyncObservers() {
        // 監聽 Core Data 保存事件
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] _ in
                self?.scheduleSync()
            }
            .store(in: &cancellables)
        
        // 監聽應用程式狀態
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.checkForSync()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Sync Management
    
    /// 開始同步
    func startSync() async {
        guard !syncInProgress else {
            print("⚠️ 同步已進行中，跳過")
            return
        }
        
        syncInProgress = true
        isSyncing = true
        syncError = nil
        syncProgress = 0.0
        
        do {
            if isInitialSync {
                try await performInitialSync()
            } else {
                try await performIncrementalSync()
            }
            
            lastSyncDate = Date()
            isInitialSync = false
            print("✅ 同步完成")
        } catch {
            syncError = error.localizedDescription
            print("❌ 同步失敗: \(error.localizedDescription)")
        }
        
        isSyncing = false
        syncInProgress = false
    }
    
    /// 執行初始同步
    private func performInitialSync() async throws {
        print("🔄 開始初始同步...")
        
        // 1. 上傳本地數據到 CloudKit
        syncProgress = 0.1
        try await uploadLocalData()
        
        // 2. 下載 CloudKit 數據到本地
        syncProgress = 0.5
        try await downloadCloudKitData()
        
        // 3. 解決衝突
        syncProgress = 0.8
        try await resolveConflicts()
        
        syncProgress = 1.0
    }
    
    /// 執行增量同步
    private func performIncrementalSync() async throws {
        print("🔄 開始增量同步...")
        
        // 1. 檢查變更
        syncProgress = 0.2
        let changes = try await fetchChanges()
        
        // 2. 上傳本地變更
        syncProgress = 0.4
        try await uploadLocalChanges()
        
        // 3. 下載遠端變更
        syncProgress = 0.6
        try await downloadRemoteChanges(changes)
        
        // 4. 解決衝突
        syncProgress = 0.8
        try await resolveConflicts()
        
        syncProgress = 1.0
    }
    
    // MARK: - Data Upload
    
    /// 上傳本地數據
    private func uploadLocalData() async throws {
        print("📤 上傳本地數據...")
        
        // 上傳用戶資料
        try await uploadUserProfile()
        
        // 上傳訓練記錄
        try await uploadWorkouts()
        
        // 上傳個人記錄
        try await uploadPersonalRecords()
        
        // 上傳自定義動作
        try await uploadCustomExercises()
    }
    
    /// 上傳用戶資料
    private func uploadUserProfile() async throws {
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
        print("✅ 用戶資料已上傳")
    }
    
    /// 上傳訓練記錄
    private func uploadWorkouts() async throws {
        let repository = WorkoutRepository()
        let workouts = try repository.getAllWorkouts()
        
        for workout in workouts {
            let record = CKRecord(recordType: "Workout")
            record["id"] = workout.id.uuidString
            record["userId"] = workout.userId.uuidString
            record["startedAt"] = workout.startedAt
            record["endedAt"] = workout.endedAt
            record["duration"] = workout.duration ?? 0
            record["totalVolume"] = workout.totalVolume
            record["totalSets"] = workout.totalSets
            record["totalExercises"] = workout.totalExercises
            record["note"] = workout.note
            record["lastSyncDate"] = Date()
            
            try await privateDatabase.save(record)
        }
        
        print("✅ 訓練記錄已上傳 (\(workouts.count) 筆)")
    }
    
    /// 上傳個人記錄
    private func uploadPersonalRecords() async throws {
        let repository = PersonalRecordRepository()
        let records = try repository.getAllPersonalRecords()
        
        for record in records {
            let ckRecord = CKRecord(recordType: "PersonalRecord")
            ckRecord["id"] = record.id.uuidString
            ckRecord["userId"] = record.userId.uuidString
            ckRecord["exerciseId"] = record.exerciseId.uuidString
            ckRecord["weight"] = record.weight
            ckRecord["reps"] = record.reps
            ckRecord["oneRepMax"] = record.oneRepMax
            ckRecord["achievedAt"] = record.achievedAt
            ckRecord["lastSyncDate"] = Date()
            
            try await privateDatabase.save(ckRecord)
        }
        
        print("✅ 個人記錄已上傳 (\(records.count) 筆)")
    }
    
    /// 上傳自定義動作
    private func uploadCustomExercises() async throws {
        let repository = ExerciseRepository()
        let exercises = try repository.getCustomExercises()
        
        for exercise in exercises {
            let record = CKRecord(recordType: "CustomExercise")
            record["id"] = exercise.id.uuidString
            record["userId"] = exercise.userId?.uuidString
            record["name"] = exercise.name
            record["categoryId"] = exercise.categoryId.uuidString
            record["muscleGroups"] = exercise.muscleGroups
            record["lastSyncDate"] = Date()
            
            try await privateDatabase.save(record)
        }
        
        print("✅ 自定義動作已上傳 (\(exercises.count) 筆)")
    }
    
    // MARK: - Data Download
    
    /// 下載 CloudKit 數據
    private func downloadCloudKitData() async throws {
        print("📥 下載 CloudKit 數據...")
        
        // 下載用戶資料
        try await downloadUserProfile()
        
        // 下載訓練記錄
        try await downloadWorkouts()
        
        // 下載個人記錄
        try await downloadPersonalRecords()
        
        // 下載自定義動作
        try await downloadCustomExercises()
    }
    
    /// 下載用戶資料
    private func downloadUserProfile() async throws {
        let query = CKQuery(recordType: "UserProfile", predicate: NSPredicate(value: true))
        let results = try await privateDatabase.records(matching: query)
        
        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                let profile = UserProfile.shared
                profile.name = record["name"] as? String ?? ""
                profile.email = record["email"] as? String ?? ""
                profile.gender = record["gender"] as? String ?? "不指定"
                profile.age = record["age"] as? Int ?? 0
                profile.height = record["height"] as? Double ?? 0
                profile.currentWeight = record["currentWeight"] as? Double ?? 0
                profile.targetWeight = record["targetWeight"] as? Double ?? 0
                profile.weeklyGoal = record["weeklyGoal"] as? Int ?? 4
                
                profile.save()
            }
        }
        
        print("✅ 用戶資料已下載")
    }
    
    /// 下載訓練記錄
    private func downloadWorkouts() async throws {
        let query = CKQuery(recordType: "Workout", predicate: NSPredicate(value: true))
        let results = try await privateDatabase.records(matching: query)
        
        let repository = WorkoutRepository()
        
        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                // 檢查是否已存在
                if let idString = record["id"] as? String,
                   let id = UUID(uuidString: idString) {
                    let existingWorkout = try repository.getWorkout(by: id)
                    if existingWorkout == nil {
                        // 創建新的訓練記錄
                        let workout = Workout(
                            id: id,
                            userId: UUID(uuidString: record["userId"] as? String ?? "") ?? UUID(),
                            startedAt: record["startedAt"] as? Date ?? Date(),
                            endedAt: record["endedAt"] as? Date,
                            duration: record["duration"] as? Int,
                            totalVolume: record["totalVolume"] as? Double ?? 0,
                            totalSets: record["totalSets"] as? Int ?? 0,
                            totalExercises: record["totalExercises"] as? Int ?? 0,
                            note: record["note"] as? String,
                            templateId: nil,
                            exercises: [],
                            createdAt: Date(),
                            updatedAt: Date()
                        )
                        
                        try repository.create(workout: workout)
                    }
                }
            }
        }
        
        print("✅ 訓練記錄已下載")
    }
    
    /// 下載個人記錄
    private func downloadPersonalRecords() async throws {
        let query = CKQuery(recordType: "PersonalRecord", predicate: NSPredicate(value: true))
        let results = try await privateDatabase.records(matching: query)
        
        let repository = PersonalRecordRepository()
        
        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                if let idString = record["id"] as? String,
                   let id = UUID(uuidString: idString) {
                    let existingRecord = try repository.getPersonalRecord(by: id)
                    if existingRecord == nil {
                        let personalRecord = PersonalRecord(
                            id: id,
                            userId: UUID(uuidString: record["userId"] as? String ?? "") ?? UUID(),
                            exerciseId: UUID(uuidString: record["exerciseId"] as? String ?? "") ?? UUID(),
                            weight: record["weight"] as? Double ?? 0,
                            reps: record["reps"] as? Int ?? 0,
                            oneRepMax: record["oneRepMax"] as? Double ?? 0,
                            achievedAt: record["achievedAt"] as? Date ?? Date(),
                            createdAt: Date(),
                            updatedAt: Date()
                        )
                        
                        try repository.create(personalRecord: personalRecord)
                    }
                }
            }
        }
        
        print("✅ 個人記錄已下載")
    }
    
    /// 下載自定義動作
    private func downloadCustomExercises() async throws {
        let query = CKQuery(recordType: "CustomExercise", predicate: NSPredicate(value: true))
        let results = try await privateDatabase.records(matching: query)
        
        let repository = ExerciseRepository()
        
        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                if let idString = record["id"] as? String,
                   let id = UUID(uuidString: idString) {
                    let existingExercise = try repository.getExercise(by: id)
                    if existingExercise == nil {
                        let exercise = Exercise(
                            id: id,
                            name: record["name"] as? String ?? "",
                            nameEn: nil,
                            categoryId: UUID(), // 需要提供 categoryId
                            category: nil,
                            type: Exercise.ExerciseType.freeWeight, // 需要提供 type
                            muscleGroups: record["muscleGroups"] as? [String] ?? [],
                            targetMuscles: [],
                            primaryMuscleGroup: nil,
                            movementPattern: nil,
                            description: nil,
                            videoURL: nil,
                            imageURL: nil,
                            isSystem: false,
                            userId: UUID(uuidString: record["userId"] as? String ?? ""),
                            isActive: true,
                            displayOrder: nil,
                            createdAt: Date(),
                            updatedAt: Date()
                        )
                        
                        try repository.create(exercise: exercise)
                    }
                }
            }
        }
        
        print("✅ 自定義動作已下載")
    }
    
    // MARK: - Change Detection
    
    /// 獲取變更
    private func fetchChanges() async throws -> [String: Any] {
        // 這裡可以實現更複雜的變更檢測邏輯
        // 目前返回空字典
        return [:]
    }
    
    /// 上傳本地變更
    private func uploadLocalChanges() async throws {
        // 實現增量上傳邏輯
        print("📤 上傳本地變更...")
    }
    
    /// 下載遠端變更
    private func downloadRemoteChanges(_ changes: [String: Any]) async throws {
        // 實現增量下載邏輯
        print("📥 下載遠端變更...")
    }
    
    // MARK: - Conflict Resolution
    
    /// 解決衝突
    private func resolveConflicts() async throws {
        print("🔧 解決數據衝突...")
        // 實現衝突解決邏輯
        // 優先使用最新的數據
    }
    
    // MARK: - Helper Methods
    
    /// 安排同步
    private func scheduleSync() {
        // 延遲同步，避免頻繁操作
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            Task {
                await self.startSync()
            }
        }
    }
    
    /// 檢查是否需要同步
    private func checkForSync() {
        // 檢查上次同步時間
        if let lastSync = lastSyncDate {
            let timeSinceLastSync = Date().timeIntervalSince(lastSync)
            if timeSinceLastSync > 300 { // 5分鐘
                Task {
                    await startSync()
                }
            }
        }
    }
    
    /// 手動同步
    func manualSync() {
        Task {
            await startSync()
        }
    }
    
    /// 開始完整同步
    func startFullSync() async {
        isInitialSync = true
        await startSync()
    }
    
    /// 開始增量同步
    func startIncrementalSync() async {
        isInitialSync = false
        await startSync()
    }
    
    /// 重置同步狀態
    func resetSyncState() {
        isInitialSync = true
        lastSyncDate = nil
        syncError = nil
        syncProgress = 0.0
    }
}

// MARK: - Extensions

extension CloudKitSyncService {
    /// 檢查同步狀態
    var syncStatus: String {
        if isSyncing {
            return "同步中... \(Int(syncProgress * 100))%"
        } else if let error = syncError {
            return "同步失敗: \(error)"
        } else if let lastSync = lastSyncDate {
            return "上次同步: \(lastSync.formatted(date: .abbreviated, time: .shortened))"
        } else {
            return "尚未同步"
        }
    }
}