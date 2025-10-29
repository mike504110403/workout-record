import Foundation
import SwiftUI

/// 重量格式化工具
struct WeightFormatter {
    static let shared = WeightFormatter()
    
    private init() {}
    
    // MARK: - Instance Methods
    
    /// 根據全域設定格式化重量顯示
    /// - Parameters:
    ///   - weight: 重量值（以公斤為基準）
    ///   - unit: 指定單位（如果為 nil 則使用全域設定）
    /// - Returns: 格式化後的字串，包含單位
    func format(_ weight: Double, unit: User.WeightUnit? = nil) -> String {
        let targetUnit = unit ?? GlobalSettingsManager.shared.weightUnit
        let convertedWeight = convert(weight, to: targetUnit)
        return String(format: "%.1f %@", convertedWeight, targetUnit.symbol)
    }
    
    /// 只格式化數值，不包含單位
    func formatValue(_ weight: Double, unit: User.WeightUnit? = nil) -> String {
        let targetUnit = unit ?? GlobalSettingsManager.shared.weightUnit
        let convertedWeight = convert(weight, to: targetUnit)
        return String(format: "%.1f", convertedWeight)
    }
    
    /// 獲取當前單位符號
    func currentUnitSymbol() -> String {
        return GlobalSettingsManager.shared.weightUnit.symbol
    }
    
    /// 轉換重量到指定單位
    /// - Parameters:
    ///   - weight: 重量值（以公斤為基準）
    ///   - unit: 目標單位
    /// - Returns: 轉換後的重量值
    func convert(_ weight: Double, to unit: User.WeightUnit) -> Double {
        switch unit {
        case .kg:
            return weight
        case .lb:
            return weight * 2.20462
        }
    }
    
    /// 從指定單位轉換回公斤
    /// - Parameters:
    ///   - weight: 重量值
    ///   - unit: 來源單位
    /// - Returns: 公斤值
    func convertToKg(_ weight: Double, from unit: User.WeightUnit) -> Double {
        switch unit {
        case .kg:
            return weight
        case .lb:
            return weight / 2.20462
        }
    }
    
    // MARK: - Static Methods (Convenience)
    
    /// 靜態方法：格式化重量（包含單位）
    static func format(_ weight: Double, unit: User.WeightUnit) -> String {
        return shared.format(weight, unit: unit)
    }
    
    /// 靜態方法：轉換為公斤
    static func toKilograms(_ weight: Double, from unit: User.WeightUnit) -> Double {
        return shared.convertToKg(weight, from: unit)
    }
}

// MARK: - View Extension

extension View {
    /// 監聽重量單位變化並自動刷新視圖
    func observeWeightUnit() -> some View {
        self.environmentObject(GlobalSettingsManager.shared)
    }
}

// MARK: - Double Extension

extension Double {
    /// 格式化為重量字串（包含單位）
    var formattedWeight: String {
        WeightFormatter.shared.format(self)
    }
    
    /// 格式化為重量數值（不含單位）
    var formattedWeightValue: String {
        WeightFormatter.shared.formatValue(self)
    }
    
    /// 轉換到當前設定的單位
    var inCurrentUnit: Double {
        WeightFormatter.shared.convert(self, to: GlobalSettingsManager.shared.weightUnit)
    }
}

