import Foundation
import SwiftUI
import Combine

/// Onboarding 狀態管理
class OnboardingState: ObservableObject {
    @AppStorage("hasCompletedOnboarding") var hasCompleted = false
    @Published var currentStep = 0
    
    // 用戶輸入的資料
    @Published var weight: String = ""
    @Published var height: String = ""
    @Published var gender: String = "不指定"
    @Published var age: String = ""
    @Published var targetWeight: String = ""
    @Published var weeklyGoal: Int = 4
    
    /// 驗證當前步驟是否可以繼續
    func canProceed(from step: Int) -> Bool {
        switch step {
        case 0: return true  // 歡迎頁
        case 1: return !weight.isEmpty  // 基本資訊
        case 2: return true  // 目標設定（可選）
        case 3: return true  // 完成頁
        default: return false
        }
    }
    
    /// 完成 Onboarding 並保存數據
    func complete() {
        // 保存用戶資料
        let profile = UserProfile.shared
        
        if let weightValue = Double(weight) {
            profile.currentWeight = weightValue
        }
        
        if let heightValue = Double(height) {
            profile.height = heightValue
        }
        
        profile.gender = gender
        
        if let ageValue = Int(age) {
            profile.age = ageValue
        }
        
        if let targetValue = Double(targetWeight) {
            profile.targetWeight = targetValue
        }
        
        profile.weeklyGoal = weeklyGoal
        profile.save()
        
        // 如果有體重，記錄第一筆體重數據
        if let weightValue = Double(weight) {
            Task {
                do {
                    let bodyWeightRepository = BodyWeightRepository()
                    let bodyWeight = BodyWeight(
                        id: UUID(),
                        userId: UUID(), // 使用預設用戶ID
                        weight: weightValue,
                        measuredAt: Date(),
                        note: "初始體重",
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                    try bodyWeightRepository.create(bodyWeight: bodyWeight)
                } catch {
                    print("❌ 記錄初始體重失敗: \(error)")
                }
            }
        }
        
        hasCompleted = true
    }
}

