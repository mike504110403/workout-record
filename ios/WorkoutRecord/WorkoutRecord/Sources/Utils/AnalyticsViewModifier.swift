import SwiftUI

/// 分析視圖修飾符
struct AnalyticsViewModifier: ViewModifier {
    let pageName: String
    let properties: [String: Any]
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                ComprehensiveAnalyticsService.shared.trackPageEnter(pageName, properties: properties)
            }
            .onDisappear {
                ComprehensiveAnalyticsService.shared.trackPageExit(pageName, properties: properties)
            }
    }
}

/// 分析按鈕修飾符
struct AnalyticsButtonModifier: ViewModifier {
    let buttonName: String
    let pageName: String
    let properties: [String: Any]
    
    func body(content: Content) -> some View {
        content
            .onTapGesture {
                ComprehensiveAnalyticsService.shared.trackButtonClick(buttonName, pageName: pageName, properties: properties)
            }
    }
}

/// 分析功能修飾符
struct AnalyticsFeatureModifier: ViewModifier {
    let featureName: String
    let properties: [String: Any]
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                ComprehensiveAnalyticsService.shared.trackFeatureUsage(featureName, properties: properties)
            }
    }
}

// MARK: - View 擴展

extension View {
    /// 追蹤頁面瀏覽
    func trackPageView(_ pageName: String, properties: [String: Any] = [:]) -> some View {
        self.modifier(AnalyticsViewModifier(pageName: pageName, properties: properties))
    }
    
    /// 追蹤按鈕點擊
    func trackButtonClick(_ buttonName: String, pageName: String, properties: [String: Any] = [:]) -> some View {
        self.modifier(AnalyticsButtonModifier(buttonName: buttonName, pageName: pageName, properties: properties))
    }
    
    /// 追蹤功能使用
    func trackFeatureUsage(_ featureName: String, properties: [String: Any] = [:]) -> some View {
        self.modifier(AnalyticsFeatureModifier(featureName: featureName, properties: properties))
    }
}
