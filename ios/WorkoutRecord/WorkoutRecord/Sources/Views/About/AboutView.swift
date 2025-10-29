import SwiftUI

struct AboutView: View {
    @State private var showingTutorial = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 16) {
                        // App 圖示
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        VStack(spacing: 8) {
                            Text("WorkItOut")
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("版本 1.0")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text("您的專業健身記錄夥伴")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }
                
                Section("功能特色") {
                        AboutFeatureRow(
                        icon: "chart.bar.fill",
                        title: "數據分析",
                        description: "詳細的訓練數據分析與趨勢圖表"
                    )
                    
                        AboutFeatureRow(
                        icon: "trophy.fill",
                        title: "成就系統",
                        description: "激勵您持續進步的成就挑戰"
                    )
                    
                        AboutFeatureRow(
                        icon: "target",
                        title: "目標追蹤",
                        description: "設定並追蹤您的健身目標"
                    )
                    
                        AboutFeatureRow(
                        icon: "figure.walk",
                        title: "三項力量",
                        description: "專業的深蹲、臥推、硬舉記錄"
                    )
                }
                
                Section("支援") {
                    Button {
                        showingTutorial = true
                    } label: {
                        Label("新手教學", systemImage: "book")
                    }
                    
                    Link(destination: URL(string: "mailto:mike504110403@gmail.com")!) {
                        Label("聯絡我們", systemImage: "envelope")
                    }
                    
                    Link(destination: URL(string: "https://workoutrecord.app/feedback")!) {
                        Label("意見回饋", systemImage: "bubble.left")
                    }
                }
                
                Section("法律") {
                    NavigationLink {
                        AboutPrivacyPolicyView()
                    } label: {
                        Label("隱私政策", systemImage: "hand.raised")
                    }
                    
                    NavigationLink {
                        TermsOfServiceView()
                    } label: {
                        Label("服務條款", systemImage: "doc.text")
                    }
                }
                
                Section("開發資訊") {
                    HStack {
                        Text("開發者")
                        Spacer()
                        Text("Mike Lin")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("建置版本")
                        Spacer()
                        Text("1.0 (2)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("最後更新")
                        Spacer()
                        Text("2024年10月22日")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("關於")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingTutorial) {
                TutorialView()
            }
        }
    }
}

struct AboutFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct AboutPrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("隱私政策")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("最後更新：2024年10月22日")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Group {
                    Text("我們重視您的隱私")
                        .font(.headline)
                    
                    Text("WorkoutRecord 致力於保護您的個人資訊。本隱私政策說明我們如何收集、使用和保護您的資訊。")
                    
                    Text("資訊收集")
                        .font(.headline)
                    
                    Text("我們收集的資訊包括：")
                    Text("• 您主動輸入的健身數據（訓練記錄、體重等）")
                    Text("• 應用程式使用統計（用於改善服務）")
                    Text("• 設備資訊（用於技術支援）")
                    
                    Text("資訊使用")
                        .font(.headline)
                    
                    Text("您的數據主要用於：")
                    Text("• 提供個人化的健身追蹤服務")
                    Text("• 改善應用程式功能和用戶體驗")
                    Text("• 生成健身報告和趨勢分析")
                    
                    Text("數據安全")
                        .font(.headline)
                    
                    Text("我們採用業界標準的安全措施保護您的數據，包括加密存儲和傳輸。")
                    
                    Text("聯絡我們")
                        .font(.headline)
                    
                    Text("如有任何隱私相關問題，請聯絡：mike504110403@gmail.com")
                }
            }
            .padding()
        }
        .navigationTitle("隱私政策")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("服務條款")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("最後更新：2024年10月22日")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Group {
                    Text("使用條款")
                        .font(.headline)
                    
                    Text("歡迎使用 WorkoutRecord。使用本應用程式即表示您同意以下條款。")
                    
                    Text("服務說明")
                        .font(.headline)
                    
                    Text("WorkoutRecord 是一個健身記錄應用程式，幫助您追蹤訓練進度、記錄體重變化並分析健身數據。")
                    
                    Text("用戶責任")
                        .font(.headline)
                    
                    Text("• 提供準確的健身數據")
                    Text("• 定期備份重要數據")
                    Text("• 合理使用應用程式功能")
                    
                    Text("免責聲明")
                        .font(.headline)
                    
                    Text("本應用程式僅供參考，不應替代專業醫療建議。請在開始任何健身計劃前諮詢醫療專業人員。")
                    
                    Text("聯絡我們")
                        .font(.headline)
                    
                    Text("如有任何問題，請聯絡：mike504110403@gmail.com")
                }
            }
            .padding()
        }
        .navigationTitle("服務條款")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    AboutView()
}
