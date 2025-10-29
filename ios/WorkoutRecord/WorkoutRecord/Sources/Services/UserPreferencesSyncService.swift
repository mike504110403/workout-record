import Foundation
import Combine
import FirebaseFirestore

/// 用戶偏好同步服務
@MainActor
class UserPreferencesSyncService: ObservableObject {
    static let shared = UserPreferencesSyncService()
    
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    
    private let db = Firestore.firestore()
    private let globalSettings = GlobalSettingsManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupSyncObservers()
    }
    
    // MARK: - Setup
    
    private func setupSyncObservers() {
        // 監聽全局設定變化，自動同步到 Firebase
        globalSettings.$weightUnit
            .dropFirst() // 跳過初始值
            .sink { [weak self] _ in
                self?.syncPreferencesToFirebase()
            }
            .store(in: &cancellables)
        
        globalSettings.$theme
            .dropFirst()
            .sink { [weak self] _ in
                self?.syncPreferencesToFirebase()
            }
            .store(in: &cancellables)
        
        globalSettings.$oneRMFormula
            .dropFirst()
            .sink { [weak self] _ in
                self?.syncPreferencesToFirebase()
            }
            .store(in: &cancellables)
        
        globalSettings.$defaultRestTime
            .dropFirst()
            .sink { [weak self] _ in
                self?.syncPreferencesToFirebase()
            }
            .store(in: &cancellables)
        
        globalSettings.$showVolumeInStats
            .dropFirst()
            .sink { [weak self] _ in
                self?.syncPreferencesToFirebase()
            }
            .store(in: &cancellables)
        
        globalSettings.$enableHapticFeedback
            .dropFirst()
            .sink { [weak self] _ in
                self?.syncPreferencesToFirebase()
            }
            .store(in: &cancellables)
        
        globalSettings.$autoSaveWorkout
            .dropFirst()
            .sink { [weak self] _ in
                self?.syncPreferencesToFirebase()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Sync Methods
    
    /// 同步偏好設定到 Firebase
    func syncPreferencesToFirebase() {
        guard let userId = getCurrentUserId() else {
            print("❌ 無法獲取用戶 ID，跳過同步")
            return
        }
        
        isSyncing = true
        syncError = nil
        
        let preferences = UserPreferences(
            weightUnit: globalSettings.weightUnit.rawValue,
            theme: globalSettings.theme.rawValue,
            oneRMFormula: globalSettings.oneRMFormula.rawValue,
            defaultRestTime: globalSettings.defaultRestTime,
            showVolumeInStats: globalSettings.showVolumeInStats,
            enableHapticFeedback: globalSettings.enableHapticFeedback,
            autoSaveWorkout: globalSettings.autoSaveWorkout,
            lastUpdated: Date()
        )
        
        Task {
            do {
                try await db.collection("user_preferences").document(userId).setData(preferences.toDictionary())
                await MainActor.run {
                    self.isSyncing = false
                    self.lastSyncDate = Date()
                    print("✅ 用戶偏好已同步到 Firebase")
                }
            } catch {
                await MainActor.run {
                    self.isSyncing = false
                    self.syncError = error.localizedDescription
                    print("❌ 同步用戶偏好失敗: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// 從 Firebase 載入用戶偏好
    func loadPreferencesFromFirebase() async {
        guard let userId = getCurrentUserId() else {
            print("❌ 無法獲取用戶 ID，跳過載入")
            return
        }
        
        isSyncing = true
        syncError = nil
        
        do {
            let document = try await db.collection("user_preferences").document(userId).getDocument()
            
            if let data = document.data() {
                let preferences = UserPreferences.fromDictionary(data)
                
                await MainActor.run {
                    // 更新全局設定
                    self.globalSettings.weightUnit = User.WeightUnit(rawValue: preferences.weightUnit) ?? .kg
                    self.globalSettings.theme = User.AppTheme(rawValue: preferences.theme) ?? .system
                    self.globalSettings.oneRMFormula = User.OneRMFormula(rawValue: preferences.oneRMFormula) ?? .epley
                    self.globalSettings.defaultRestTime = preferences.defaultRestTime
                    self.globalSettings.showVolumeInStats = preferences.showVolumeInStats
                    self.globalSettings.enableHapticFeedback = preferences.enableHapticFeedback
                    self.globalSettings.autoSaveWorkout = preferences.autoSaveWorkout
                    
                    self.isSyncing = false
                    self.lastSyncDate = Date()
                    print("✅ 已從 Firebase 載入用戶偏好")
                }
            } else {
                await MainActor.run {
                    self.isSyncing = false
                    print("ℹ️ 沒有找到用戶偏好設定，使用預設值")
                }
            }
        } catch {
            await MainActor.run {
                self.isSyncing = false
                self.syncError = error.localizedDescription
                print("❌ 載入用戶偏好失敗: \(error.localizedDescription)")
            }
        }
    }
    
    /// 手動同步
    func manualSync() {
        Task {
            await loadPreferencesFromFirebase()
        }
    }
    
    // MARK: - Helper Methods
    
    private func getCurrentUserId() -> String? {
        // 這裡應該從認證服務獲取當前用戶 ID
        // 暫時返回 nil，實際實現時需要整合認證服務
        return nil
    }
}

// MARK: - User Preferences Data Structure
struct UserPreferences: Codable {
    let weightUnit: String
    let theme: String
    let oneRMFormula: String
    let defaultRestTime: Int
    let showVolumeInStats: Bool
    let enableHapticFeedback: Bool
    let autoSaveWorkout: Bool
    let lastUpdated: Date
    
    func toDictionary() -> [String: Any] {
        return [
            "weightUnit": weightUnit,
            "theme": theme,
            "oneRMFormula": oneRMFormula,
            "defaultRestTime": defaultRestTime,
            "showVolumeInStats": showVolumeInStats,
            "enableHapticFeedback": enableHapticFeedback,
            "autoSaveWorkout": autoSaveWorkout,
            "lastUpdated": Timestamp(date: lastUpdated)
        ]
    }
    
    static func fromDictionary(_ data: [String: Any]) -> UserPreferences {
        return UserPreferences(
            weightUnit: data["weightUnit"] as? String ?? "kg",
            theme: data["theme"] as? String ?? "system",
            oneRMFormula: data["oneRMFormula"] as? String ?? "epley",
            defaultRestTime: data["defaultRestTime"] as? Int ?? 90,
            showVolumeInStats: data["showVolumeInStats"] as? Bool ?? true,
            enableHapticFeedback: data["enableHapticFeedback"] as? Bool ?? true,
            autoSaveWorkout: data["autoSaveWorkout"] as? Bool ?? true,
            lastUpdated: (data["lastUpdated"] as? Timestamp)?.dateValue() ?? Date()
        )
    }
}
