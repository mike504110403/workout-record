import Foundation
import SwiftUI
import Combine

/// 全面用戶行為分析服務
class ComprehensiveAnalyticsService: ObservableObject {
    static let shared = ComprehensiveAnalyticsService()
    
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0.0
    @Published var lastUploadDate: Date?
    @Published var uploadError: String?
    
    // 會話管理
    private var currentSession: AnalyticsSession?
    private var sessionStartTime: Date?
    private var pageStartTimes: [String: Date] = [:]
    private var buttonClickCounts: [String: Int] = [:]
    private var pageVisitCounts: [String: Int] = [:]
    
    // 數據儲存
    private let userDefaults = UserDefaults.standard
    private let analyticsKey = "ComprehensiveAnalyticsData"
    private let maxStoredSessions = 50 // 最大儲存會話數
    private let uploadInterval: TimeInterval = 6 * 60 * 60 // 6小時上傳一次
    private let immediateUploadThreshold = 20 // 達到此數量時立即上傳
    private let maxRetryAttempts = 3 // 最大重試次數
    
    private init() {
        // 檢查隱私權同意
        if PrivacyConsentService.shared.hasConsented {
            startNewSession()
            checkAndUploadIfNeeded()
        }
    }
    
    // MARK: - 會話管理
    
    /// 開始新會話
    func startNewSession() {
        sessionStartTime = Date()
        currentSession = AnalyticsSession(
            sessionId: UUID().uuidString,
            startTime: Date(),
            appVersion: getAppVersion(),
            deviceModel: getDeviceModel(),
            systemVersion: getSystemVersion(),
            userId: getCurrentUserId()
        )
        
        // 追蹤 App 啟動
        trackAppLaunch()
    }
    
    /// 結束當前會話
    func endCurrentSession() {
        guard let session = currentSession,
              let startTime = sessionStartTime else { return }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        // 更新會話結束時間和持續時間
        var updatedSession = session
        updatedSession.endTime = endTime
        updatedSession.duration = duration
        updatedSession.pageVisits = pageVisitCounts
        updatedSession.buttonClicks = buttonClickCounts
        
        // 儲存會話數據
        storeSession(updatedSession)
        
        // 重置會話數據
        currentSession = nil
        sessionStartTime = nil
        pageStartTimes.removeAll()
        buttonClickCounts.removeAll()
        pageVisitCounts.removeAll()
    }
    
    // MARK: - 頁面追蹤
    
    /// 追蹤頁面進入
    func trackPageEnter(_ pageName: String, properties: [String: Any] = [:]) {
        pageStartTimes[pageName] = Date()
        
        // 增加頁面訪問次數
        pageVisitCounts[pageName, default: 0] += 1
        
        // 追蹤頁面瀏覽事件
        trackEvent("page_enter", properties: [
            "page_name": pageName,
            "timestamp": Date().timeIntervalSince1970,
            "session_id": currentSession?.sessionId ?? "",
            "visit_count": pageVisitCounts[pageName] ?? 1
        ])
    }
    
    /// 追蹤頁面離開
    func trackPageExit(_ pageName: String, properties: [String: Any] = [:]) {
        guard let startTime = pageStartTimes[pageName] else { return }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        // 追蹤頁面停留時間
        trackEvent("page_exit", properties: [
            "page_name": pageName,
            "duration": duration,
            "timestamp": endTime.timeIntervalSince1970,
            "session_id": currentSession?.sessionId ?? ""
        ])
        
        // 更新會話中的頁面數據
        updateSessionPageData(pageName: pageName, duration: duration)
        
        // 清除頁面開始時間
        pageStartTimes.removeValue(forKey: pageName)
    }
    
    // MARK: - 按鈕點擊追蹤
    
    /// 追蹤按鈕點擊
    func trackButtonClick(_ buttonName: String, pageName: String, properties: [String: Any] = [:]) {
        let clickKey = "\(pageName)_\(buttonName)"
        buttonClickCounts[clickKey, default: 0] += 1
        
        // 追蹤按鈕點擊事件
        trackEvent("button_click", properties: [
            "button_name": buttonName,
            "page_name": pageName,
            "click_count": buttonClickCounts[clickKey] ?? 1,
            "timestamp": Date().timeIntervalSince1970,
            "session_id": currentSession?.sessionId ?? ""
        ])
    }
    
    // MARK: - 功能使用追蹤
    
    /// 追蹤功能使用
    func trackFeatureUsage(_ featureName: String, properties: [String: Any] = [:]) {
        trackEvent("feature_usage", properties: [
            "feature_name": featureName,
            "timestamp": Date().timeIntervalSince1970,
            "session_id": currentSession?.sessionId ?? ""
        ])
    }
    
    /// 追蹤訓練相關事件
    func trackWorkoutEvent(_ eventType: WorkoutEventType, properties: [String: Any] = [:]) {
        var workoutProperties = properties
        workoutProperties["event_type"] = eventType.rawValue
        workoutProperties["timestamp"] = Date().timeIntervalSince1970
        workoutProperties["session_id"] = currentSession?.sessionId ?? ""
        
        trackEvent("workout_event", properties: workoutProperties)
    }
    
    /// 追蹤數據輸入
    func trackDataInput(_ inputType: DataInputType, properties: [String: Any] = [:]) {
        var inputProperties = properties
        inputProperties["input_type"] = inputType.rawValue
        inputProperties["timestamp"] = Date().timeIntervalSince1970
        inputProperties["session_id"] = currentSession?.sessionId ?? ""
        
        trackEvent("data_input", properties: inputProperties)
    }
    
    // MARK: - 錯誤追蹤
    
    /// 追蹤錯誤
    func trackError(_ error: Error, context: String, properties: [String: Any] = [:]) {
        var errorProperties = properties
        errorProperties["error_message"] = error.localizedDescription
        errorProperties["error_context"] = context
        errorProperties["timestamp"] = Date().timeIntervalSince1970
        errorProperties["session_id"] = currentSession?.sessionId ?? ""
        
        trackEvent("error_occurred", properties: errorProperties)
    }
    
    /// 追蹤崩潰
    func trackCrash(_ crashInfo: [String: Any]) {
        var crashProperties = crashInfo
        crashProperties["timestamp"] = Date().timeIntervalSince1970
        crashProperties["session_id"] = currentSession?.sessionId ?? ""
        
        trackEvent("app_crash", properties: crashProperties)
    }
    
    // MARK: - 數據管理
    
    /// 儲存會話數據
    private func storeSession(_ session: AnalyticsSession) {
        var sessions = getStoredSessions()
        sessions.append(session)
        
        // 限制儲存數量
        if sessions.count > maxStoredSessions {
            sessions = Array(sessions.suffix(maxStoredSessions))
        }
        
        saveSessions(sessions)
    }
    
    /// 獲取儲存的會話
    private func getStoredSessions() -> [AnalyticsSession] {
        guard let data = userDefaults.data(forKey: analyticsKey),
              let sessions = try? JSONDecoder().decode([AnalyticsSession].self, from: data) else {
            return []
        }
        return sessions
    }
    
    /// 儲存會話
    private func saveSessions(_ sessions: [AnalyticsSession]) {
        if let data = try? JSONEncoder().encode(sessions) {
            userDefaults.set(data, forKey: analyticsKey)
        }
    }
    
    /// 更新會話頁面數據
    private func updateSessionPageData(pageName: String, duration: TimeInterval) {
        guard var session = currentSession else { return }
        
        if session.pageDurations[pageName] != nil {
            session.pageDurations[pageName]! += duration
        } else {
            session.pageDurations[pageName] = duration
        }
        
        currentSession = session
    }
    
    // MARK: - 上傳管理
    
    /// 檢查並上傳
    private func checkAndUploadIfNeeded() {
        guard let lastUpload = lastUploadDate else {
            scheduleUpload()
            return
        }
        
        if Date().timeIntervalSince(lastUpload) >= uploadInterval {
            Task {
                await uploadSessions()
            }
        }
    }
    
    /// 安排上傳
    private func scheduleUpload() {
        DispatchQueue.main.asyncAfter(deadline: .now() + uploadInterval) {
            Task {
                await self.uploadSessions()
            }
        }
    }
    
    /// 上傳會話數據
    func uploadSessions() async {
        await MainActor.run {
            isUploading = true
            uploadProgress = 0.0
            uploadError = nil
        }
        
        do {
            let sessions = getStoredSessions()
            if sessions.isEmpty {
                await MainActor.run {
                    isUploading = false
                }
                return
            }
            
            // 模擬上傳進度
            for i in 0..<sessions.count {
                await MainActor.run {
                    uploadProgress = Double(i) / Double(sessions.count)
                }
                
                // 模擬上傳延遲
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            }
            
            // 上傳到 Firebase
            do {
                try await FirebaseConfigService.shared.uploadAnalyticsSessions(sessions)
            } catch {
                // 如果 Firebase 上傳失敗，記錄錯誤但不影響 App 使用
                print("⚠️ Firebase 上傳失敗: \(error.localizedDescription)")
                // 可以選擇重試或稍後上傳
            }
            
            await MainActor.run {
                lastUploadDate = Date()
                isUploading = false
                uploadProgress = 1.0
            }
            
            // 清除已上傳的會話
            clearUploadedSessions()
            
        } catch {
            await MainActor.run {
                uploadError = error.localizedDescription
                isUploading = false
            }
        }
    }
    
    /// 清除已上傳的會話
    private func clearUploadedSessions() {
        userDefaults.removeObject(forKey: analyticsKey)
    }
    
    // MARK: - 輔助方法
    
    /// 追蹤 App 啟動
    private func trackAppLaunch() {
        trackEvent("app_launch", properties: [
            "timestamp": Date().timeIntervalSince1970,
            "session_id": currentSession?.sessionId ?? ""
        ])
    }
    
    /// 追蹤事件
    private func trackEvent(_ event: String, properties: [String: Any] = [:]) {
        // 這裡可以添加額外的事件處理邏輯
        print("📊 Analytics: \(event) - \(properties)")
    }
    
    /// 獲取 App 版本
    private func getAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    /// 獲取設備型號
    private func getDeviceModel() -> String {
        return UIDevice.current.model
    }
    
    /// 獲取系統版本
    private func getSystemVersion() -> String {
        return UIDevice.current.systemVersion
    }
    
    /// 獲取當前用戶ID
    private func getCurrentUserId() -> String {
        return userDefaults.string(forKey: "CurrentUserId") ?? "anonymous"
    }
    
    /// 設置用戶ID
    func setUserId(_ userId: String) {
        userDefaults.set(userId, forKey: "CurrentUserId")
    }
    
    /// 清除用戶ID
    func clearUserId() {
        userDefaults.removeObject(forKey: "CurrentUserId")
    }
}

// MARK: - 數據模型

/// 分析會話
struct AnalyticsSession: Codable {
    let sessionId: String
    let startTime: Date
    var endTime: Date?
    var duration: TimeInterval?
    let appVersion: String
    let deviceModel: String
    let systemVersion: String
    let userId: String
    var pageVisits: [String: Int] = [:]
    var pageDurations: [String: TimeInterval] = [:]
    var buttonClicks: [String: Int] = [:]
    var events: [ComprehensiveAnalyticsEvent] = []
}

/// 分析事件
struct ComprehensiveAnalyticsEvent: Codable {
    let event: String
    let properties: [String: Any]
    let timestamp: Date
    let sessionId: String
    
    enum CodingKeys: String, CodingKey {
        case event, timestamp, sessionId
        case properties
    }
    
    init(event: String, properties: [String: Any], timestamp: Date, sessionId: String) {
        self.event = event
        self.properties = properties
        self.timestamp = timestamp
        self.sessionId = sessionId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        event = try container.decode(String.self, forKey: .event)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        
        if let propertiesData = try? container.decode(Data.self, forKey: .properties),
           let properties = try? JSONSerialization.jsonObject(with: propertiesData) as? [String: Any] {
            self.properties = properties
        } else {
            self.properties = [:]
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(event, forKey: .event)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(sessionId, forKey: .sessionId)
        
        if let propertiesData = try? JSONSerialization.data(withJSONObject: properties) {
            try container.encode(propertiesData, forKey: .properties)
        }
    }
}

/// 訓練事件類型
enum WorkoutEventType: String, CaseIterable, Codable {
    case workoutStarted = "workout_started"
    case workoutCompleted = "workout_completed"
    case workoutPaused = "workout_paused"
    case workoutResumed = "workout_resumed"
    case exerciseAdded = "exercise_added"
    case setCompleted = "set_completed"
    case restTimerStarted = "rest_timer_started"
    case restTimerStopped = "rest_timer_stopped"
}

/// 數據輸入類型
enum DataInputType: String, CaseIterable, Codable {
    case bodyWeight = "body_weight"
    case exerciseData = "exercise_data"
    case personalInfo = "personal_info"
    case goalSetting = "goal_setting"
    case customExercise = "custom_exercise"
}
