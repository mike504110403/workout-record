import Foundation
import CoreData

/// CoreData 管理核心
/// 負責初始化、配置和管理 CoreData 持久化容器
class CoreDataStack {
    
    // MARK: - Singleton
    
    static let shared = CoreDataStack()
    
    private init() {
        // 私有初始化，確保單例
    }
    
    // MARK: - Core Data Stack
    
    /// 持久化容器
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "WorkoutRecord")
        
        // 配置存儲描述
        let description = container.persistentStoreDescriptions.first
        
        // ⚠️ 檢查是否需要強制重建資料庫（模型變更時）
        if UserDefaults.standard.bool(forKey: "ForceResetCoreData") {
            print("⚠️ 檢測到強制重置標記，刪除舊資料庫...")
            if let url = description?.url {
                let fileManager = FileManager.default
                
                // 刪除主資料庫文件
                if fileManager.fileExists(atPath: url.path) {
                    try? fileManager.removeItem(at: url)
                    print("  ✓ 已刪除: \(url.lastPathComponent)")
                }
                
                // 刪除 -shm 文件（shared memory）
                let shmURL = URL(fileURLWithPath: url.path + "-shm")
                if fileManager.fileExists(atPath: shmURL.path) {
                    try? fileManager.removeItem(at: shmURL)
                    print("  ✓ 已刪除: \(shmURL.lastPathComponent)")
                }
                
                // 刪除 -wal 文件（write-ahead log）
                let walURL = URL(fileURLWithPath: url.path + "-wal")
                if fileManager.fileExists(atPath: walURL.path) {
                    try? fileManager.removeItem(at: walURL)
                    print("  ✓ 已刪除: \(walURL.lastPathComponent)")
                }
            }
            UserDefaults.standard.removeObject(forKey: "ForceResetCoreData")
            print("✅ 舊資料庫已完全刪除，將用新模型重建")
        }
        
        // 啟用自動遷移
        description?.shouldMigrateStoreAutomatically = true
        description?.shouldInferMappingModelAutomatically = true
        
        // 未來 CloudKit 同步準備（現在註解掉）
        // description?.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
        //     containerIdentifier: "iCloud.com.yourcompany.WorkoutRecord"
        // )
        
        // 加載持久化存儲
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                // 處理錯誤
                print("❌ CoreData 載入失敗: \(error)")
                print("   錯誤詳情: \(error.userInfo)")
                
                // 如果是模型不兼容的錯誤，刪除舊資料庫重新創建
                if let url = storeDescription.url {
                    let fileManager = FileManager.default
                    
                    print("⚠️ 刪除不兼容的資料庫並重新創建...")
                    
                    // 刪除主資料庫文件
                    try? fileManager.removeItem(at: url)
                    
                    // 刪除 -shm 和 -wal 文件
                    let shmURL = URL(fileURLWithPath: url.path + "-shm")
                    let walURL = URL(fileURLWithPath: url.path + "-wal")
                    try? fileManager.removeItem(at: shmURL)
                    try? fileManager.removeItem(at: walURL)
                    
                    // 重置初始化標記
                    UserDefaults.standard.removeObject(forKey: "DefaultDataInitialized")
                    
                    // 重新載入
                    container.loadPersistentStores { newDescription, newError in
                        if let newError = newError {
                            print("❌ 重新載入仍然失敗: \(newError)")
                        } else {
                            print("✅ CoreData 重新載入成功")
                        }
                    }
                }
            } else {
                print("✅ CoreData 載入成功: \(storeDescription)")
            }
        }
        
        // 配置自動合併策略
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        return container
    }()
    
    /// 主上下文（用於 UI 操作）
    var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    // MARK: - Background Context
    
    /// 創建後台上下文（用於大量數據操作）
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }
    
    // MARK: - Save Context
    
    /// 保存主上下文
    func saveContext() {
        let context = viewContext
        if context.hasChanges {
            do {
                try context.save()
                print("✅ CoreData 保存成功")
            } catch {
                let nserror = error as NSError
                print("❌ CoreData 保存失敗: \(nserror), \(nserror.userInfo)")
            }
        }
    }
    
    /// 保存指定上下文
    func save(context: NSManagedObjectContext) throws {
        if context.hasChanges {
            try context.save()
        }
    }
    
    // MARK: - Batch Operations
    
    /// 批量刪除
    func batchDelete<T: NSManagedObject>(
        _ entityType: T.Type,
        predicate: NSPredicate? = nil
    ) throws {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = T.fetchRequest()
        fetchRequest.predicate = predicate
        
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeObjectIDs
        
        let result = try viewContext.execute(deleteRequest) as? NSBatchDeleteResult
        let objectIDArray = result?.result as? [NSManagedObjectID] ?? []
        let changes = [NSDeletedObjectsKey: objectIDArray]
        
        NSManagedObjectContext.mergeChanges(
            fromRemoteContextSave: changes,
            into: [viewContext]
        )
    }
    
    // MARK: - Utilities
    
    /// 重置數據庫（僅用於測試）
    func resetDatabase() {
        let entities = persistentContainer.managedObjectModel.entities
        for entity in entities {
            if let name = entity.name {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: name)
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                
                do {
                    try viewContext.execute(deleteRequest)
                    print("🗑️ 已清空: \(name)")
                } catch {
                    print("❌ 清空失敗: \(name), \(error)")
                }
            }
        }
        
        saveContext()
    }
    
    /// 獲取數據庫文件大小
    func getDatabaseSize() -> String {
        guard let url = persistentContainer.persistentStoreDescriptions.first?.url else {
            return "Unknown"
        }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
        } catch {
            print("❌ 無法獲取數據庫大小: \(error)")
        }
        
        return "Unknown"
    }
}

// MARK: - Fetch Request Helpers

extension CoreDataStack {
    /// 通用 fetch 方法
    func fetch<T: NSManagedObject>(
        _ entityType: T.Type,
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = nil,
        limit: Int? = nil,
        context: NSManagedObjectContext? = nil
    ) throws -> [T] {
        let entityName = String(describing: entityType)
        let fetchRequest = NSFetchRequest<T>(entityName: entityName)
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        
        if let limit = limit {
            fetchRequest.fetchLimit = limit
        }
        
        let contextToUse = context ?? viewContext
        return try contextToUse.fetch(fetchRequest)
    }
    
    /// 計數ㄈ
    func count<T: NSManagedObject>(
        _ entityType: T.Type,
        predicate: NSPredicate? = nil,
        context: NSManagedObjectContext? = nil
    ) throws -> Int {
        let entityName = String(describing: entityType)
        let fetchRequest = NSFetchRequest<T>(entityName: entityName)
        fetchRequest.predicate = predicate
        
        let contextToUse = context ?? viewContext
        return try contextToUse.count(for: fetchRequest)
    }
}

