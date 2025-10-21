import SwiftUI
import Combine

@main
struct WorkoutRecordApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(appState)
        }
    }
}

/// App-wide state management
class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    
    init() {
        // ⚠️ 重要：必須在任何 UI 渲染前同步執行 CoreData 檢查
        checkAndResetCoreDataIfNeededSync()
        
        // 異步初始化默認數據
        initializeApp()
    }
    
    private func checkAndResetCoreDataIfNeededSync() {
        // 🔴 臨時強制重置（調試用）
        // 取消下行註解可強制重建資料庫，然後再註解回來
        // UserDefaults.standard.removeObject(forKey: "CoreDataModelVersion") // ⚠️ 已禁用
        
        // 使用版本號來追蹤模型變更
        let currentModelVersion = "2.3" // 修復分類 UUID 為固定值
        let savedModelVersion = UserDefaults.standard.string(forKey: "CoreDataModelVersion")
        
        print("🔍 檢查 CoreData 版本: 儲存版本=\(savedModelVersion ?? "nil"), 當前版本=\(currentModelVersion)")
        
        // ⚠️ 如果版本不符，立即刪除資料庫文件（在 CoreData 初始化之前）
        if savedModelVersion == nil || savedModelVersion != currentModelVersion {
            print("⚠️ 需要重建資料庫")
            
            // 獲取所有可能的資料庫文件路徑
            let fileManager = FileManager.default
            
            // 方法1: Application Support 目錄
            if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                print("📁 檢查目錄: \(appSupportURL.path)")
                deleteDatabase(at: appSupportURL, fileManager: fileManager)
            }
            
            // 方法2: Documents 目錄（某些情況下 CoreData 可能用這個）
            if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                print("📁 檢查目錄: \(documentsURL.path)")
                deleteDatabase(at: documentsURL, fileManager: fileManager)
            }
            
            // 方法3: Library 目錄
            if let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
                print("📁 檢查目錄: \(libraryURL.path)")
                deleteDatabase(at: libraryURL, fileManager: fileManager)
            }
            
            // 重置所有相關標記
            UserDefaults.standard.removeObject(forKey: "ForceResetCoreData")
            UserDefaults.standard.removeObject(forKey: "DefaultDataInitialized")
            UserDefaults.standard.set(currentModelVersion, forKey: "CoreDataModelVersion")
            UserDefaults.standard.synchronize() // 強制立即保存
            
            print("✅ 資料庫刪除完成，標記已更新")
        } else {
            print("✅ CoreData 模型版本檢查通過")
        }
    }
    
    private func deleteDatabase(at baseURL: URL, fileManager: FileManager) {
        let storeURL = baseURL.appendingPathComponent("WorkoutRecord.sqlite")
        let shmURL = baseURL.appendingPathComponent("WorkoutRecord.sqlite-shm")
        let walURL = baseURL.appendingPathComponent("WorkoutRecord.sqlite-wal")
        
        var deletedCount = 0
        
        if fileManager.fileExists(atPath: storeURL.path) {
            do {
                try fileManager.removeItem(at: storeURL)
                print("  ✓ 已刪除: \(storeURL.path)")
                deletedCount += 1
            } catch {
                print("  ✗ 刪除失敗: \(storeURL.path) - \(error)")
            }
        }
        
        if fileManager.fileExists(atPath: shmURL.path) {
            do {
                try fileManager.removeItem(at: shmURL)
                print("  ✓ 已刪除: \(shmURL.path)")
                deletedCount += 1
            } catch {
                print("  ✗ 刪除失敗: \(shmURL.path) - \(error)")
            }
        }
        
        if fileManager.fileExists(atPath: walURL.path) {
            do {
                try fileManager.removeItem(at: walURL)
                print("  ✓ 已刪除: \(walURL.path)")
                deletedCount += 1
            } catch {
                print("  ✗ 刪除失敗: \(walURL.path) - \(error)")
            }
        }
        
        if deletedCount == 0 {
            print("  ℹ️ 此目錄下沒有找到資料庫文件")
        }
    }
    
    private func initializeApp() {
        Task {
            do {
                // 初始化默認數據（系統動作、示例模板等）
                try await DataMigrationService().initializeDefaultData()
                print("✅ App 初始化完成")
            } catch {
                print("❌ App 初始化失敗: \(error)")
            }
        }
    }
}

