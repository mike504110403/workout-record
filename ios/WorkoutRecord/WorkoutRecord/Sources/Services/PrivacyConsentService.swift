import Foundation
import SwiftUI
import Combine

/// 隱私權同意服務
class PrivacyConsentService: ObservableObject {
    static let shared = PrivacyConsentService()
    
    @Published var hasAgreedToAnalytics = false
    @Published var hasAgreedToPrivacy = false
    @Published var consentDate: Date?
    @Published var showConsentView = false
    
    private init() {
        loadConsentStatus()
        checkIfConsentNeeded()
    }
    
    // MARK: - 同意狀態管理
    
    /// 載入同意狀態
    private func loadConsentStatus() {
        hasAgreedToAnalytics = UserDefaults.standard.bool(forKey: "HasAgreedToAnalytics")
        hasAgreedToPrivacy = UserDefaults.standard.bool(forKey: "HasAgreedToPrivacy")
        
        if let date = UserDefaults.standard.object(forKey: "PrivacyConsentDate") as? Date {
            consentDate = date
        }
    }
    
    /// 檢查是否需要顯示同意視圖
    private func checkIfConsentNeeded() {
        // 如果用戶沒有同意，顯示同意視圖
        if !hasAgreedToAnalytics || !hasAgreedToPrivacy {
            showConsentView = true
        }
    }
    
    /// 用戶同意
    func userConsented() {
        hasAgreedToAnalytics = true
        hasAgreedToPrivacy = true
        consentDate = Date()
        showConsentView = false
        
        // 保存到 UserDefaults
        UserDefaults.standard.set(true, forKey: "HasAgreedToAnalytics")
        UserDefaults.standard.set(true, forKey: "HasAgreedToPrivacy")
        UserDefaults.standard.set(consentDate, forKey: "PrivacyConsentDate")
        
        // 啟用分析功能
        enableAnalytics()
    }
    
    /// 用戶拒絕
    func userDeclined() {
        hasAgreedToAnalytics = false
        hasAgreedToPrivacy = false
        showConsentView = false
        
        // 停用分析功能
        disableAnalytics()
    }
    
    /// 重置同意狀態
    func resetConsent() {
        hasAgreedToAnalytics = false
        hasAgreedToPrivacy = false
        consentDate = nil
        showConsentView = true
        
        // 清除 UserDefaults
        UserDefaults.standard.removeObject(forKey: "HasAgreedToAnalytics")
        UserDefaults.standard.removeObject(forKey: "HasAgreedToPrivacy")
        UserDefaults.standard.removeObject(forKey: "PrivacyConsentDate")
        
        // 停用分析功能
        disableAnalytics()
    }
    
    // MARK: - 分析功能控制
    
    /// 啟用分析功能
    private func enableAnalytics() {
        // 啟用 ComprehensiveAnalyticsService
        // 這裡可以添加啟用分析的邏輯
        print("✅ 分析功能已啟用")
    }
    
    /// 停用分析功能
    private func disableAnalytics() {
        // 停用 ComprehensiveAnalyticsService
        // 清除本地分析數據
        UserDefaults.standard.removeObject(forKey: "ComprehensiveAnalyticsData")
        print("❌ 分析功能已停用")
    }
    
    // MARK: - 同意狀態檢查
    
    /// 檢查是否已同意
    var hasConsented: Bool {
        return hasAgreedToAnalytics && hasAgreedToPrivacy
    }
    
    /// 檢查同意是否過期（可選）
    var isConsentExpired: Bool {
        guard let consentDate = consentDate else { return true }
        
        // 設定同意有效期（例如：1年）
        let expirationDate = Calendar.current.date(byAdding: .year, value: 1, to: consentDate) ?? Date()
        return Date() > expirationDate
    }
    
    /// 獲取同意狀態描述
    var consentStatusDescription: String {
        if hasConsented {
            return "已同意隱私政策"
        } else {
            return "未同意隱私政策"
        }
    }
}

// MARK: - 隱私權同意修飾符

struct PrivacyConsentModifier: ViewModifier {
    @StateObject private var privacyService = PrivacyConsentService.shared
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $privacyService.showConsentView) {
                PrivacyConsentView(isPresented: $privacyService.showConsentView)
            }
    }
}

extension View {
    /// 添加隱私權同意檢查
    func checkPrivacyConsent() -> some View {
        self.modifier(PrivacyConsentModifier())
    }
}
