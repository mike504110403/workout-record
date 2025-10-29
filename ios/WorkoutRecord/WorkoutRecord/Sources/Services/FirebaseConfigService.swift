import Foundation
import FirebaseCore
import FirebaseAnalytics
import FirebaseFirestore
import FirebaseCrashlytics
import Combine

/// Firebase 配置服務
class FirebaseConfigService: ObservableObject {
    static let shared = FirebaseConfigService()
    
    @Published var isInitialized = false
    @Published var isConnected = false
    @Published var connectionError: String?
    
    private let db = Firestore.firestore()
    
    private init() {
        configureFirebase()
    }
    
    // MARK: - Firebase 配置
    
    /// 配置 Firebase
    private func configureFirebase() {
        // 檢查是否已經初始化
        guard FirebaseApp.app() == nil else {
            isInitialized = true
            checkConnection()
            return
        }
        
        // 配置 Firebase
        FirebaseApp.configure()
        
        // 配置 Crashlytics
        configureCrashlytics()
        
        isInitialized = true
        
        // 延遲檢查連接，避免初始化問題
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.checkConnection()
        }
    }
    
    /// 配置 Crashlytics
    private func configureCrashlytics() {
        // 啟用 Crashlytics 收集
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        
        // 設置用戶標識符（如果有的話）
        // Crashlytics.crashlytics().setUserID("user_id")
    }
    
    /// 檢查 Firebase 連接
    private func checkConnection() {
        Task {
            do {
                // 嘗試連接 Firestore - 使用更簡單的測試
                let _ = try await db.collection("analytics_sessions").getDocuments()
                await MainActor.run {
                    isConnected = true
                    connectionError = nil
                }
            } catch {
                await MainActor.run {
                    isConnected = false
                    // 提供更友好的錯誤訊息
                    if error.localizedDescription.contains("permission") {
                        connectionError = "Firebase 權限設定錯誤，請檢查安全規則"
                    } else if error.localizedDescription.contains("network") || error.localizedDescription.contains("offline") {
                        connectionError = "網路連接失敗，請檢查網路設定"
                    } else {
                        connectionError = "Firebase 連接失敗: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    // MARK: - 分析數據上傳
    
    /// 上傳分析會話數據
    func uploadAnalyticsSessions(_ sessions: [AnalyticsSession]) async throws {
        guard isConnected else {
            throw FirebaseError.notConnected
        }
        
        let batch = db.batch()
        
        for session in sessions {
            let sessionRef = db.collection("analytics_sessions").document(session.sessionId)
            
            // 轉換為 Firestore 格式
            let sessionData: [String: Any] = [
                "sessionId": session.sessionId,
                "startTime": Timestamp(date: session.startTime),
                "endTime": session.endTime != nil ? Timestamp(date: session.endTime!) : NSNull(),
                "duration": session.duration ?? 0,
                "appVersion": session.appVersion,
                "deviceModel": session.deviceModel,
                "systemVersion": session.systemVersion,
                "userId": session.userId,
                "pageVisits": session.pageVisits,
                "pageDurations": session.pageDurations,
                "buttonClicks": session.buttonClicks,
                "uploadedAt": Timestamp(date: Date())
            ]
            
            batch.setData(sessionData, forDocument: sessionRef)
        }
        
        try await batch.commit()
    }
    
    /// 上傳分析事件數據
    func uploadAnalyticsEvents(_ events: [ComprehensiveAnalyticsEvent]) async throws {
        guard isConnected else {
            throw FirebaseError.notConnected
        }
        
        let batch = db.batch()
        
        for event in events {
            let eventRef = db.collection("analytics_events").document()
            
            let eventData: [String: Any] = [
                "event": event.event,
                "properties": event.properties,
                "timestamp": Timestamp(date: event.timestamp),
                "sessionId": event.sessionId,
                "uploadedAt": Timestamp(date: Date())
            ]
            
            batch.setData(eventData, forDocument: eventRef)
        }
        
        try await batch.commit()
    }
    
    /// 上傳用戶行為數據
    func uploadUserBehavior(_ behaviorData: [String: Any]) async throws {
        guard isConnected else {
            throw FirebaseError.notConnected
        }
        
        let behaviorRef = db.collection("user_behavior").document()
        
        let data: [String: Any] = [
            "behaviorData": behaviorData,
            "uploadedAt": Timestamp(date: Date())
        ]
        
        try await behaviorRef.setData(data)
    }
    
    // MARK: - 重新連接
    
    /// 重新檢查 Firebase 連接
    func recheckConnection() {
        checkConnection()
    }
    
    /// 重新配置 Firebase
    func reconfigureFirebase() {
        configureFirebase()
    }
    
    // MARK: - 錯誤處理
    
    enum FirebaseError: LocalizedError {
        case notConnected
        case uploadFailed(String)
        case configurationFailed
        
        var errorDescription: String? {
            switch self {
            case .notConnected:
                return "Firebase 未連接"
            case .uploadFailed(let message):
                return "上傳失敗: \(message)"
            case .configurationFailed:
                return "Firebase 配置失敗"
            }
        }
    }
}

// MARK: - Firebase 分析擴展

extension FirebaseConfigService {
    /// 追蹤自定義事件
    func trackCustomEvent(_ eventName: String, parameters: [String: Any] = [:]) {
        guard isInitialized else { return }
        
        Analytics.logEvent(eventName, parameters: parameters)
    }
    
    /// 追蹤頁面瀏覽
    func trackScreenView(_ screenName: String, screenClass: String? = nil) {
        guard isInitialized else { return }
        
        var parameters: [String: Any] = [
            AnalyticsParameterScreenName: screenName
        ]
        
        if let screenClass = screenClass {
            parameters[AnalyticsParameterScreenClass] = screenClass
        }
        
        Analytics.logEvent(AnalyticsEventScreenView, parameters: parameters)
    }
    
    /// 追蹤用戶屬性
    func setUserProperty(_ value: String?, forName: String) {
        guard isInitialized else { return }
        
        Analytics.setUserProperty(value, forName: forName)
    }
    
    /// 設置用戶 ID
    func setUserId(_ userId: String) {
        guard isInitialized else { return }
        
        Analytics.setUserID(userId)
        Crashlytics.crashlytics().setUserID(userId)
    }
    
    /// 記錄自定義錯誤到 Crashlytics
    func recordError(_ error: Error, userInfo: [String: Any] = [:]) {
        guard isInitialized else { return }
        
        let nsError = error as NSError
        let userInfoDict = nsError.userInfo.merging(userInfo) { _, new in new }
        let customError = NSError(domain: nsError.domain, code: nsError.code, userInfo: userInfoDict)
        
        Crashlytics.crashlytics().record(error: customError)
    }
    
    /// 記錄自定義鍵值對到 Crashlytics
    func setCustomValue(_ value: Any, forKey key: String) {
        guard isInitialized else { return }
        
        Crashlytics.crashlytics().setCustomValue(value, forKey: key)
    }
}
