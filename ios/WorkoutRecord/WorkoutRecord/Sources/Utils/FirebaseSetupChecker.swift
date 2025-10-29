import Foundation
import FirebaseCore
import FirebaseFirestore
import Combine

/// Firebase 設定檢查工具
class FirebaseSetupChecker: ObservableObject {
    static let shared = FirebaseSetupChecker()
    
    @Published var isConfigured = false
    @Published var configurationErrors: [String] = []
    @Published var setupStatus: SetupStatus = .notStarted
    
    enum SetupStatus {
        case notStarted
        case inProgress
        case completed
        case failed
    }
    
    private init() {
        checkConfiguration()
    }
    
    /// 檢查 Firebase 配置
    func checkConfiguration() {
        configurationErrors.removeAll()
        
        // 檢查 Firebase 是否已初始化
        if FirebaseApp.app() == nil {
            configurationErrors.append("Firebase 未初始化")
            setupStatus = .failed
            return
        }
        
        // 檢查 GoogleService-Info.plist
        if !checkGoogleServiceInfo() {
            configurationErrors.append("缺少 GoogleService-Info.plist 檔案")
            setupStatus = .failed
            return
        }
        
        // 檢查 Firestore 連接
        checkFirestoreConnection()
    }
    
    /// 檢查 GoogleService-Info.plist
    private func checkGoogleServiceInfo() -> Bool {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path) else {
            return false
        }
        
        // 檢查必要的鍵值
        let requiredKeys = ["PROJECT_ID", "BUNDLE_ID", "API_KEY"]
        for key in requiredKeys {
            if plist[key] == nil {
                configurationErrors.append("GoogleService-Info.plist 缺少 \(key)")
                return false
            }
        }
        
        return true
    }
    
    /// 檢查 Firestore 連接
    private func checkFirestoreConnection() {
        setupStatus = .inProgress
        
        Task {
            do {
                let db = Firestore.firestore()
                let _ = try await db.collection("test").document("connection").getDocument()
                
                await MainActor.run {
                    isConfigured = true
                    setupStatus = .completed
                }
            } catch {
                await MainActor.run {
                    configurationErrors.append("Firestore 連接失敗: \(error.localizedDescription)")
                    setupStatus = .failed
                }
            }
        }
    }
    
    /// 獲取設定指南
    func getSetupGuide() -> String {
        return """
        Firebase 設定指南：
        
        1. 前往 Firebase Console：
           https://console.firebase.google.com/
        
        2. 創建新專案：
           - 專案名稱：WorkItOut-Analytics
           - 啟用 Google Analytics
        
        3. 添加 iOS App：
           - Bundle ID：com.mikelin.workitout
           - App 暱稱：WorkItOut
        
        4. 下載設定檔：
           - 下載 GoogleService-Info.plist
           - 拖拽到 Xcode 專案中
        
        5. 啟用 Firestore：
           - 創建 Firestore 資料庫
           - 選擇測試模式
        
        6. 設定安全規則：
           - 複製安全規則到 Firestore
           - 發布規則
        
        7. 在 Xcode 中添加 Firebase SDK：
           - 使用 Swift Package Manager
           - 添加 Firebase/Analytics
           - 添加 Firebase/Firestore
        """
    }
    
    /// 獲取安全規則
    func getSecurityRules() -> String {
        return FirebaseSecurityRules.firestoreRules
    }
    
    /// 重新檢查配置
    func recheckConfiguration() {
        checkConfiguration()
    }
}
