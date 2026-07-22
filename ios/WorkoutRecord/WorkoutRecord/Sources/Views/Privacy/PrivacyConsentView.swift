import SwiftUI

/// 隱私權同意視圖 - 簡潔條款式設計
struct PrivacyConsentView: View {
    @Binding var isPresented: Bool
    @State private var hasAgreedToAnalytics = false
    @State private var hasAgreedToPrivacy = false
    @State private var showingPrivacyPolicy = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 標題區域
            VStack(spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)
                
                Text("隱私權同意")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("使用前請閱讀並同意以下條款")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 60)
            .padding(.bottom, 30)
            
            // 條款內容區域
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 數據收集摘要
                    TermsSection(
                        title: "資料收集範圍",
                        items: [
                            "Apple ID 登入資訊（姓名、電子郵件）",
                            "應用程式使用數據與操作行為",
                            "設備資訊與錯誤報告",
                            "訓練記錄僅儲存於您的裝置本機"
                        ]
                    )
                    
                    // 數據用途
                    TermsSection(
                        title: "資料使用目的",
                        items: [
                            "提供帳號登入功能",
                            "改善應用程式功能與用戶體驗",
                            "分析與修復技術問題",
                            "提供更符合需求的服務"
                        ]
                    )
                    
                    // 隱私保護
                    TermsSection(
                        title: "隱私保護承諾",
                        items: [
                            "訓練記錄儲存在您的裝置本機，不會上傳雲端",
                            "僅收集必要的帳號資訊",
                            "不用於廣告或行銷目的",
                            "不與第三方分享您的個人資料"
                        ]
                    )
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 20)
            }
            
            // 同意選項區域
            VStack(alignment: .leading, spacing: 16) {
                CheckboxRow(
                    isChecked: $hasAgreedToAnalytics,
                    text: "我同意收集匿名使用數據以改善服務"
                )
                
                CheckboxRow(
                    isChecked: $hasAgreedToPrivacy,
                    text: "我已閱讀並同意隱私政策"
                )
                
                // 查看完整隱私政策
                Button {
                    showingPrivacyPolicy = true
                } label: {
                    Text("查看完整隱私權政策")
                        .font(.footnote)
                        .foregroundColor(.blue)
                        .underline()
                }
                .padding(.leading, 32)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 20)
            .background(Color(.secondarySystemBackground))
            
            // 底部按鈕區域
            VStack(spacing: 12) {
                Button {
                    if hasAgreedToAnalytics && hasAgreedToPrivacy {
                        UserDefaults.standard.set(true, forKey: "HasAgreedToAnalytics")
                        UserDefaults.standard.set(true, forKey: "HasAgreedToPrivacy")
                        UserDefaults.standard.set(Date(), forKey: "PrivacyConsentDate")
                        isPresented = false
                    }
                } label: {
                    Text("同意並繼續")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            (hasAgreedToAnalytics && hasAgreedToPrivacy) ? Color.blue : Color.gray
                        )
                        .cornerRadius(12)
                }
                .disabled(!hasAgreedToAnalytics || !hasAgreedToPrivacy)
                
                Button {
                    exit(0)
                } label: {
                    Text("不同意")
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 20)
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView()
        }
    }
}

// MARK: - 條款區塊
struct TermsSection: View {
    let title: String
    let items: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.body)
                            .foregroundColor(.secondary)
                        Text(item)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - 勾選框行
struct CheckboxRow: View {
    @Binding var isChecked: Bool
    let text: String
    
    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isChecked.toggle()
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundColor(isChecked ? .blue : .gray)
                
                Text(text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                
                Spacer()
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    PrivacyConsentView(isPresented: .constant(true))
}
