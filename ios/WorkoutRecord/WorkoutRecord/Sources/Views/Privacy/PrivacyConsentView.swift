import SwiftUI

/// 隱私權同意視圖
struct PrivacyConsentView: View {
    @Binding var isPresented: Bool
    @State private var hasAgreedToAnalytics = false
    @State private var hasAgreedToPrivacy = false
    @State private var showingPrivacyPolicy = false
    
    var body: some View {
        ZStack {
            // 背景
            Color(.systemBackground)
                .ignoresSafeArea()
            
            // 主要內容
            VStack(spacing: 0) {
                // 標題區域
                VStack(spacing: 12) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                    
                    Text("隱私權同意")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("我們重視您的隱私，請了解我們如何保護您的數據")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                .padding(.horizontal, 24)
                
                // 內容區域
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                    
                        // 數據收集說明
                        DataCollectionCard()
                    
                        // 不會收集的數據
                        DataProtectionCard()
                    
                        // 數據用途說明
                        DataUsageCard()
                        
                        // 隱私保護說明
                        PrivacyProtectionCard()
                    
                        // 同意選項
                        ConsentOptionsCard(
                            hasAgreedToAnalytics: $hasAgreedToAnalytics,
                            hasAgreedToPrivacy: $hasAgreedToPrivacy,
                            showingPrivacyPolicy: $showingPrivacyPolicy
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
                
                // 底部按鈕區域
                VStack(spacing: 12) {
                    Button("同意並繼續") {
                        if hasAgreedToAnalytics && hasAgreedToPrivacy {
                            // 保存用戶同意
                            UserDefaults.standard.set(true, forKey: "HasAgreedToAnalytics")
                            UserDefaults.standard.set(true, forKey: "HasAgreedToPrivacy")
                            UserDefaults.standard.set(Date(), forKey: "PrivacyConsentDate")
                            
                            isPresented = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasAgreedToAnalytics || !hasAgreedToPrivacy)
                    .frame(maxWidth: .infinity)
                    
                    Button("不同意") {
                        // 用戶不同意，退出 App
                        exit(0)
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .background(Color(.systemBackground))
            }
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView()
        }
    }
}

// MARK: - 數據收集卡片
struct DataCollectionCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
                Text("我們會收集的數據")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                DataItem(
                    icon: "chart.bar.fill",
                    title: "操作數據",
                    description: "頁面瀏覽、按鈕點擊、功能使用情況",
                    color: .green
                )
                
                DataItem(
                    icon: "iphone",
                    title: "設備資訊",
                    description: "設備型號、系統版本、App 版本",
                    color: .green
                )
                
                DataItem(
                    icon: "clock.fill",
                    title: "使用統計",
                    description: "App 使用時長、錯誤報告",
                    color: .green
                )
            }
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - 數據保護卡片
struct DataProtectionCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.title2)
                Text("我們不會收集的數據")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                DataItem(
                    icon: "person.fill",
                    title: "個人資訊",
                    description: "姓名、電子郵件、電話號碼",
                    color: .red
                )
                
                DataItem(
                    icon: "figure.strengthtraining.traditional",
                    title: "訓練數據",
                    description: "體重、訓練記錄、個人目標",
                    color: .red
                )
                
                DataItem(
                    icon: "location.fill",
                    title: "位置資訊",
                    description: "GPS 位置、地址資訊",
                    color: .red
                )
            }
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - 數據用途卡片
struct DataUsageCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "gear")
                    .foregroundColor(.blue)
                    .font(.title2)
                Text("數據用途")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                UsageItem(text: "改善 App 功能和用戶體驗")
                UsageItem(text: "分析用戶行為模式")
                UsageItem(text: "修復錯誤和提升穩定性")
                UsageItem(text: "提供個性化建議")
            }
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - 隱私保護卡片
struct PrivacyProtectionCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "shield.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                Text("隱私保護")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                UsageItem(text: "所有數據匿名化處理")
                UsageItem(text: "加密傳輸和儲存")
                UsageItem(text: "不與第三方分享")
                UsageItem(text: "您可以隨時停用分析功能")
            }
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - 同意選項卡片
struct ConsentOptionsCard: View {
    @Binding var hasAgreedToAnalytics: Bool
    @Binding var hasAgreedToPrivacy: Bool
    @Binding var showingPrivacyPolicy: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.blue)
                    .font(.title2)
                Text("請選擇您的同意選項")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                Toggle("我同意收集操作數據和設備資訊", isOn: $hasAgreedToAnalytics)
                    .toggleStyle(SwitchToggleStyle())
                
                Toggle("我同意隱私政策條款", isOn: $hasAgreedToPrivacy)
                    .toggleStyle(SwitchToggleStyle())
                
                Button("查看完整隱私政策") {
                    showingPrivacyPolicy = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - 數據項目
struct DataItem: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - 用途項目
struct UsageItem: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
            Text(text)
                .font(.body)
        }
    }
}

#Preview {
    PrivacyConsentView(isPresented: .constant(true))
}
