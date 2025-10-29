import Foundation
import SwiftUI
import Combine
import FirebaseAnalytics

/// 使用者行為分析服務
/// 整合 Firebase Analytics 追蹤用戶行為
class AnalyticsService: ObservableObject {
    static let shared = AnalyticsService()
    
    private var isDebugMode: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    private init() {
        print("📊 Analytics Service 初始化 (\(isDebugMode ? "DEBUG" : "RELEASE"))")
    }
    
    // MARK: - Event Tracking
    
    /// 追蹤 App 啟動
    func trackAppLaunch() {
        logEvent("app_launch", parameters: [
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    /// 追蹤訓練開始
    func trackWorkoutStart(workoutType: String, templateUsed: Bool) {
        logEvent("workout_start", parameters: [
            "workout_type": workoutType,
            "template_used": templateUsed,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    /// 追蹤訓練完成
    func trackWorkoutComplete(duration: TimeInterval, exerciseCount: Int, totalVolume: Double) {
        logEvent("workout_complete", parameters: [
            "duration_minutes": duration / 60,
            "exercise_count": exerciseCount,
            "total_volume": totalVolume,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    /// 追蹤體重記錄
    func trackBodyWeightRecorded(weight: Double, isFirstRecord: Bool) {
        logEvent("body_weight_recorded", parameters: [
            "weight": weight,
            "is_first_record": isFirstRecord,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    /// 追蹤成就解鎖
    func trackAchievementUnlocked(achievementId: String, achievementTitle: String) {
        logEvent("achievement_unlocked", parameters: [
            "achievement_id": achievementId,
            "achievement_title": achievementTitle,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    /// 追蹤功能使用
    func trackFeatureUsage(feature: String, action: String) {
        logEvent("feature_usage", parameters: [
            "feature": feature,
            "action": action,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    /// 追蹤頁面瀏覽
    func trackPageView(page: String) {
        logEvent("page_view", parameters: [
            "page": page,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    /// 追蹤設定變更
    func trackSettingChanged(setting: String, oldValue: Any, newValue: Any) {
        logEvent("setting_changed", parameters: [
            "setting": setting,
            "old_value": String(describing: oldValue),
            "new_value": String(describing: newValue),
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    // MARK: - User Properties
    
    /// 設定使用者屬性
    func setUserProperty(_ key: String, value: Any) {
        UserDefaults.standard.set(value, forKey: "analytics_user_\(key)")
    }
    
    /// 取得使用者屬性
    func getUserProperty(_ key: String) -> Any? {
        return UserDefaults.standard.object(forKey: "analytics_user_\(key)")
    }
    
    // MARK: - Analytics Data
    
    /// 取得分析數據
    func getAnalyticsData() -> AnalyticsData {
        let events = loadEvents()
        return AnalyticsData(events: events)
    }
    
    /// 清除分析數據
    func clearAnalyticsData() {
        UserDefaults.standard.removeObject(forKey: "analytics_events")
    }
    
    // MARK: - Private Methods
    
    func logEvent(_ eventName: String, parameters: [String: Any]) {
        // 1. 本地記錄（用於開發和調試）
        let event = StandardAnalyticsEvent(
            name: eventName,
            parameters: parameters,
            timestamp: Date()
        )
        
        var events = loadEvents()
        events.append(event)
        
        // 只保留最近 1000 個事件
        if events.count > 1000 {
            events = Array(events.suffix(1000))
        }
        
        saveEvents(events)
        
        // 2. Firebase Analytics 記錄
        var firebaseParams: [String: Any] = parameters
        firebaseParams["environment"] = isDebugMode ? "debug" : "production"
        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            firebaseParams["app_version"] = appVersion
        }
        
        // 轉換參數為 Firebase 支援的類型
        let convertedParams = convertParametersForFirebase(firebaseParams)
        Analytics.logEvent(eventName, parameters: convertedParams)
        
        // 在開發模式下打印事件
        #if DEBUG
        print("📊 Analytics: \(eventName) - \(parameters)")
        #endif
    }
    
    /// 轉換參數為 Firebase 支援的類型
    private func convertParametersForFirebase(_ parameters: [String: Any]) -> [String: Any] {
        var converted: [String: Any] = [:]
        
        for (key, value) in parameters {
            switch value {
            case let stringValue as String:
                converted[key] = stringValue
            case let intValue as Int:
                converted[key] = intValue
            case let doubleValue as Double:
                converted[key] = doubleValue
            case let boolValue as Bool:
                converted[key] = boolValue
            case let dateValue as Date:
                converted[key] = dateValue.timeIntervalSince1970
            default:
                converted[key] = String(describing: value)
            }
        }
        
        return converted
    }
    
    private func loadEvents() -> [StandardAnalyticsEvent] {
        guard let data = UserDefaults.standard.data(forKey: "analytics_events"),
              let events = try? JSONDecoder().decode([StandardAnalyticsEvent].self, from: data) else {
            return []
        }
        return events
    }
    
    private func saveEvents(_ events: [StandardAnalyticsEvent]) {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: "analytics_events")
        }
    }
}

// MARK: - Data Models

struct StandardAnalyticsEvent: Codable {
    let name: String
    let parameters: [String: Any]
    let timestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case name, timestamp
    }
    
    init(name: String, parameters: [String: Any], timestamp: Date) {
        self.name = name
        self.parameters = parameters
        self.timestamp = timestamp
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        
        // 簡化處理，實際應用中可能需要更複雜的參數解碼
        parameters = [:]
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(timestamp, forKey: .timestamp)
        
        // 簡化處理，實際應用中可能需要更複雜的參數編碼
    }
}

struct AnalyticsData {
    let events: [StandardAnalyticsEvent]
    
    var totalEvents: Int {
        events.count
    }
    
    var uniqueEvents: [String] {
        Array(Set(events.map { $0.name }))
    }
    
    func eventsForType(_ eventType: String) -> [StandardAnalyticsEvent] {
        events.filter { $0.name == eventType }
    }
    
    var workoutEvents: [StandardAnalyticsEvent] {
        events.filter { $0.name.contains("workout") }
    }
    
    var achievementEvents: [StandardAnalyticsEvent] {
        events.filter { $0.name.contains("achievement") }
    }
}

// MARK: - Analytics View

struct AnalyticsView: View {
    @StateObject private var analyticsService = AnalyticsService.shared
    @State private var analyticsData: AnalyticsData?
    
    var body: some View {
        NavigationStack {
            List {
                if let data = analyticsData {
                    Section("總覽") {
                        HStack {
                            Text("總事件數")
                            Spacer()
                            Text("\(data.totalEvents)")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("事件類型")
                            Spacer()
                            Text("\(data.uniqueEvents.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Section("訓練分析") {
                        let workoutEvents = data.workoutEvents
                        HStack {
                            Text("訓練事件")
                            Spacer()
                            Text("\(workoutEvents.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Section("成就分析") {
                        let achievementEvents = data.achievementEvents
                        HStack {
                            Text("成就事件")
                            Spacer()
                            Text("\(achievementEvents.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Section("事件詳情") {
                        ForEach(data.uniqueEvents, id: \.self) { eventType in
                            let eventCount = data.eventsForType(eventType).count
                            HStack {
                                Text(eventType)
                                Spacer()
                                Text("\(eventCount)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    ProgressView("載入分析數據...")
                }
            }
            .navigationTitle("使用分析")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清除數據") {
                        analyticsService.clearAnalyticsData()
                        loadAnalyticsData()
                    }
                }
            }
            .onAppear {
                loadAnalyticsData()
            }
        }
    }
    
    private func loadAnalyticsData() {
        analyticsData = analyticsService.getAnalyticsData()
    }
}

#Preview {
    AnalyticsView()
}
