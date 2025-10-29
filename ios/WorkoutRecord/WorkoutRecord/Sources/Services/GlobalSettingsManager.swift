import Foundation
import Combine
import SwiftUI

/// 全局設定管理器
@MainActor
class GlobalSettingsManager: ObservableObject {
    static let shared = GlobalSettingsManager()
    
    // MARK: - Published Properties
    @Published var weightUnit: User.WeightUnit = .kg
    @Published var theme: User.AppTheme = .system
    @Published var oneRMFormula: User.OneRMFormula = .epley
    @Published var defaultRestTime: Int = 90 // 秒
    @Published var showVolumeInStats: Bool = true
    @Published var enableHapticFeedback: Bool = true
    @Published var autoSaveWorkout: Bool = true
    
    // MARK: - Private Properties
    private let userDefaults = UserDefaults.standard
    private let settingsKey = "GlobalSettings"
    
    // MARK: - Initialization
    private init() {
        loadSettings()
    }
    
    // MARK: - Settings Management
    
    /// 載入設定
    private func loadSettings() {
        if let data = userDefaults.data(forKey: settingsKey),
           let settings = try? JSONDecoder().decode(SettingsData.self, from: data) {
            self.weightUnit = settings.weightUnit
            self.theme = settings.theme
            self.oneRMFormula = settings.oneRMFormula
            self.defaultRestTime = settings.defaultRestTime
            self.showVolumeInStats = settings.showVolumeInStats
            self.enableHapticFeedback = settings.enableHapticFeedback
            self.autoSaveWorkout = settings.autoSaveWorkout
        }
    }
    
    /// 儲存設定
    func saveSettings() {
        let settings = SettingsData(
            weightUnit: weightUnit,
            theme: theme,
            oneRMFormula: oneRMFormula,
            defaultRestTime: defaultRestTime,
            showVolumeInStats: showVolumeInStats,
            enableHapticFeedback: enableHapticFeedback,
            autoSaveWorkout: autoSaveWorkout
        )
        
        if let data = try? JSONEncoder().encode(settings) {
            userDefaults.set(data, forKey: settingsKey)
        }
    }
    
    /// 更新設定並自動儲存
    func updateSetting<T>(_ keyPath: WritableKeyPath<GlobalSettingsManager, T>, value: T) {
        // 直接設置屬性值，避免 keyPath 下標問題
        switch keyPath {
        case \.weightUnit:
            weightUnit = value as! User.WeightUnit
        case \.theme:
            theme = value as! User.AppTheme
        case \.oneRMFormula:
            oneRMFormula = value as! User.OneRMFormula
        case \.defaultRestTime:
            defaultRestTime = value as! Int
        case \.showVolumeInStats:
            showVolumeInStats = value as! Bool
        case \.enableHapticFeedback:
            enableHapticFeedback = value as! Bool
        case \.autoSaveWorkout:
            autoSaveWorkout = value as! Bool
        default:
            break
        }
        saveSettings()
    }
    
    /// 重置為預設值
    func resetToDefaults() {
        weightUnit = .kg
        theme = .system
        oneRMFormula = .epley
        defaultRestTime = 90
        showVolumeInStats = true
        enableHapticFeedback = true
        autoSaveWorkout = true
        saveSettings()
    }
}

// MARK: - Settings Data Structure
struct SettingsData: Codable {
    let weightUnit: User.WeightUnit
    let theme: User.AppTheme
    let oneRMFormula: User.OneRMFormula
    let defaultRestTime: Int
    let showVolumeInStats: Bool
    let enableHapticFeedback: Bool
    let autoSaveWorkout: Bool
}

// MARK: - Enums (已移至 User.swift)
// WeightUnit, AppTheme, OneRMFormula 定義已移至 Models/User.swift

// MARK: - Extensions
extension GlobalSettingsManager {
    /// 獲取當前主題的 ColorScheme
    var colorScheme: ColorScheme? {
        switch theme {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
    
    /// 轉換重量單位
    func convertWeight(_ weight: Double, from fromUnit: User.WeightUnit, to toUnit: User.WeightUnit) -> Double {
        if fromUnit == toUnit { return weight }
        
        switch (fromUnit, toUnit) {
        case (.kg, .lb):
            return weight * 2.20462
        case (.lb, .kg):
            return weight / 2.20462
        default:
            return weight
        }
    }
    
    /// 格式化重量顯示
    func formatWeight(_ weight: Double) -> String {
        return String(format: "%.1f %@", weight, weightUnit.symbol)
    }
    
    /// 根據當前單位獲取重量值
    func getWeightValue(from set: WorkoutSet) -> Double {
        switch weightUnit {
        case .kg:
            return set.weight
        case .lb:
            return set.weightLb
        }
    }
    
    /// 根據當前單位獲取容量值
    func getVolumeValue(from set: WorkoutSet) -> Double {
        switch weightUnit {
        case .kg:
            return set.volume
        case .lb:
            return set.volumeLb
        }
    }
}
