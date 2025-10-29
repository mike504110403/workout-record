import SwiftUI
import Combine

/// App設定管理 (已棄用，請使用 GlobalSettingsManager)
@available(*, deprecated, message: "請使用 GlobalSettingsManager.shared")
class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    // MARK: - 設定項目 (向後兼容)
    
    @AppStorage("weightUnit") var weightUnit: String = "kg"
    @AppStorage("theme") var theme: String = "system"
    @AppStorage("oneRMFormula") var oneRMFormula: String = "epley"
    @AppStorage("defaultRestTime") var defaultRestTime: Int = 90
    @AppStorage("enableAutoRestTimer") var enableAutoRestTimer: Bool = true
    @AppStorage("enableHapticFeedback") var enableHapticFeedback: Bool = true
    
    // MARK: - 主題計算屬性
    
    var colorScheme: ColorScheme? {
        switch theme {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil // 跟隨系統
        }
    }
    
    // MARK: - 重置設定
    
    func resetToDefaults() {
        weightUnit = "kg"
        theme = "system"
        oneRMFormula = "epley"
        defaultRestTime = 90
        enableAutoRestTimer = true
        enableHapticFeedback = true
    }
}

/// 個人資料管理
class UserProfile: ObservableObject {
    static let shared = UserProfile()
    
    @AppStorage("userName") var name: String = ""
    @AppStorage("userEmail") var email: String = "user@example.com"
    @AppStorage("userGender") var gender: String = "不指定"
    @AppStorage("userAge") var age: Int = 0
    @AppStorage("userHeight") var height: Double = 0
    @AppStorage("userCurrentWeight") var currentWeight: Double = 0
    @AppStorage("userTargetWeight") var targetWeight: Double = 0
    @AppStorage("weeklyWorkoutGoal") var weeklyGoal: Int = 4
    
    // MARK: - 儲存方法
    
    func save() {
        // AppStorage 會自動保存，這裡可以添加額外邏輯
        objectWillChange.send()
    }
}

