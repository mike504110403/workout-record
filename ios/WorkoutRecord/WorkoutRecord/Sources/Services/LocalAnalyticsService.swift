import Foundation
import SwiftUI
import Combine

/// 本地分析服務
class LocalAnalyticsService: ObservableObject {
    static let shared = LocalAnalyticsService()
    
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0.0
    @Published var lastUploadDate: Date?
    @Published var uploadError: String?
    
    private let userDefaults = UserDefaults.standard
    private let analyticsKey = "LocalAnalyticsData"
    private let maxStoredEvents = 1000 // 最大儲存事件數
    private let uploadInterval: TimeInterval = 24 * 60 * 60 // 24小時上傳一次
    
    private init() {
        // 檢查是否需要上傳
        checkAndUploadIfNeeded()
    }
    
    // MARK: - 事件追蹤
    
    /// 追蹤事件
    func trackEvent(_ event: String, properties: [String: Any] = [:]) {
        let eventData = LocalAnalyticsEvent(
            event: event,
            properties: properties,
            timestamp: Date(),
            sessionId: getCurrentSessionId(),
            userId: getCurrentUserId()
        )
        
        storeEvent(eventData)
        
        // 如果事件數超過限制，立即上傳
        if getStoredEventsCount() > maxStoredEvents {
            Task {
                await uploadEvents()
            }
        }
    }
    
    /// 追蹤頁面瀏覽
    func trackScreenView(_ screenName: String, properties: [String: Any] = [:]) {
        var screenProperties = properties
        screenProperties["screen_name"] = screenName
        screenProperties["timestamp"] = Date().timeIntervalSince1970
        
        trackEvent("screen_view", properties: screenProperties)
    }
    
    /// 追蹤按鈕點擊
    func trackButtonClick(_ buttonName: String, screenName: String, properties: [String: Any] = [:]) {
        var clickProperties = properties
        clickProperties["button_name"] = buttonName
        clickProperties["screen_name"] = screenName
        clickProperties["timestamp"] = Date().timeIntervalSince1970
        
        trackEvent("button_click", properties: clickProperties)
    }
    
    /// 追蹤功能使用
    func trackFeatureUsage(_ featureName: String, properties: [String: Any] = [:]) {
        var featureProperties = properties
        featureProperties["feature_name"] = featureName
        featureProperties["timestamp"] = Date().timeIntervalSince1970
        
        trackEvent("feature_usage", properties: featureProperties)
    }
    
    /// 追蹤用戶行為
    func trackUserBehavior(_ behavior: String, properties: [String: Any] = [:]) {
        var behaviorProperties = properties
        behaviorProperties["behavior"] = behavior
        behaviorProperties["timestamp"] = Date().timeIntervalSince1970
        
        trackEvent("user_behavior", properties: behaviorProperties)
    }
    
    // MARK: - 數據管理
    
    /// 儲存事件
    private func storeEvent(_ event: LocalAnalyticsEvent) {
        var events = getStoredEvents()
        events.append(event)
        
        // 限制儲存數量
        if events.count > maxStoredEvents {
            events = Array(events.suffix(maxStoredEvents))
        }
        
        saveEvents(events)
    }
    
    /// 獲取儲存的事件
    private func getStoredEvents() -> [LocalAnalyticsEvent] {
        guard let data = userDefaults.data(forKey: analyticsKey),
              let events = try? JSONDecoder().decode([LocalAnalyticsEvent].self, from: data) else {
            return []
        }
        return events
    }
    
    /// 儲存事件
    private func saveEvents(_ events: [LocalAnalyticsEvent]) {
        if let data = try? JSONEncoder().encode(events) {
            userDefaults.set(data, forKey: analyticsKey)
        }
    }
    
    /// 獲取事件數量
    private func getStoredEventsCount() -> Int {
        return getStoredEvents().count
    }
    
    /// 清除已上傳的事件
    private func clearUploadedEvents() {
        userDefaults.removeObject(forKey: analyticsKey)
    }
    
    // MARK: - 上傳管理
    
    /// 檢查並上傳
    private func checkAndUploadIfNeeded() {
        guard let lastUpload = lastUploadDate else {
            // 首次使用，24小時後上傳
            scheduleUpload()
            return
        }
        
        if Date().timeIntervalSince(lastUpload) >= uploadInterval {
            Task {
                await uploadEvents()
            }
        }
    }
    
    /// 安排上傳
    private func scheduleUpload() {
        DispatchQueue.main.asyncAfter(deadline: .now() + uploadInterval) {
            Task {
                await self.uploadEvents()
            }
        }
    }
    
    /// 上傳事件
    func uploadEvents() async {
        await MainActor.run {
            isUploading = true
            uploadProgress = 0.0
            uploadError = nil
        }
        
        do {
            let events = getStoredEvents()
            if events.isEmpty {
                await MainActor.run {
                    isUploading = false
                }
                return
            }
            
            // 模擬上傳進度
            for i in 0..<events.count {
                await MainActor.run {
                    uploadProgress = Double(i) / Double(events.count)
                }
                
                // 模擬上傳延遲
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            }
            
            // 這裡可以實作實際的上傳邏輯
            // await uploadToServer(events)
            
            await MainActor.run {
                lastUploadDate = Date()
                isUploading = false
                uploadProgress = 1.0
            }
            
            // 清除已上傳的事件
            clearUploadedEvents()
            
        } catch {
            await MainActor.run {
                uploadError = error.localizedDescription
                isUploading = false
            }
        }
    }
    
    // MARK: - 輔助方法
    
    /// 獲取當前會話ID
    private func getCurrentSessionId() -> String {
        if let sessionId = userDefaults.string(forKey: "CurrentSessionId") {
            return sessionId
        } else {
            let sessionId = UUID().uuidString
            userDefaults.set(sessionId, forKey: "CurrentSessionId")
            return sessionId
        }
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

/// 分析事件
struct LocalAnalyticsEvent: Codable {
    let event: String
    let properties: [String: Any]
    let timestamp: Date
    let sessionId: String
    let userId: String
    
    enum CodingKeys: String, CodingKey {
        case event, timestamp, sessionId, userId
        case properties
    }
    
    init(event: String, properties: [String: Any], timestamp: Date, sessionId: String, userId: String) {
        self.event = event
        self.properties = properties
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.userId = userId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        event = try container.decode(String.self, forKey: .event)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        userId = try container.decode(String.self, forKey: .userId)
        
        // 處理 properties 字典
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
        try container.encode(userId, forKey: .userId)
        
        // 編碼 properties 字典
        if let propertiesData = try? JSONSerialization.data(withJSONObject: properties) {
            try container.encode(propertiesData, forKey: .properties)
        }
    }
}
