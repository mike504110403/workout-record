import SwiftUI

struct TutorialView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // 標題
                VStack(alignment: .leading, spacing: 8) {
                    Text("歡迎使用 WorkoutRecord")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("完整的健身訓練記錄工具")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
                
                Divider()
                
                // 快速開始
                TutorialSection(
                    title: "快速開始",
                    icon: "flame.fill",
                    iconColor: .orange
                ) {
                    TutorialStep(
                        number: 1,
                        title: "開始訓練",
                        description: "點擊首頁的「開始訓練」按鈕，選擇訓練模板或自由訓練"
                    )
                    
                    TutorialStep(
                        number: 2,
                        title: "新增動作",
                        description: "點擊「新增動作」，從動作庫選擇您要訓練的項目"
                    )
                    
                    TutorialStep(
                        number: 3,
                        title: "記錄組數",
                        description: "點擊「新增組數」，輸入重量和次數，系統會自動計算訓練容量"
                    )
                    
                    TutorialStep(
                        number: 4,
                        title: "完成訓練",
                        description: "完成所有組數後，點擊「結束訓練」保存記錄"
                    )
                }
                
                Divider()
                
                // 主要功能
                TutorialSection(
                    title: "主要功能",
                    icon: "star.fill",
                    iconColor: .blue
                ) {
                    TutorialFeatureCard(
                        icon: "house.fill",
                        title: "首頁",
                        description: "查看訓練統計、今日訓練進度和快速開始訓練"
                    )
                    
                    TutorialFeatureCard(
                        icon: "figure.strengthtraining.traditional",
                        title: "訓練",
                        description: "記錄訓練過程，支援自由訓練和模板訓練"
                    )
                    
                    TutorialFeatureCard(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "數據",
                        description: "查看訓練容量趨勢、肌群分析和個人記錄"
                    )
                    
                    TutorialFeatureCard(
                        icon: "calendar",
                        title: "歷史",
                        description: "查看過往訓練記錄，支援日曆和列表視圖"
                    )
                    
                    TutorialFeatureCard(
                        icon: "gearshape.fill",
                        title: "設定",
                        description: "管理個人資料、目標設定和 App 偏好"
                    )
                }
                
                Divider()
                
                // 進階功能
                TutorialSection(
                    title: "進階功能",
                    icon: "sparkles",
                    iconColor: .purple
                ) {
                    AdvancedFeature(
                        icon: "target",
                        title: "目標設定",
                        description: "設定每週訓練次數和肌群容量目標，App 會追蹤您的進度並提供鼓勵"
                    )
                    
                    AdvancedFeature(
                        icon: "doc.text",
                        title: "訓練模板",
                        description: "建立自己的訓練模板，下次訓練時可以快速開始"
                    )
                    
                    AdvancedFeature(
                        icon: "list.bullet",
                        title: "動作庫",
                        description: "內建 67 個常用動作，也可以新增自定義動作"
                    )
                    
                    AdvancedFeature(
                        icon: "scalemass.fill",
                        title: "體重追蹤",
                        description: "記錄體重變化，配合訓練數據追蹤身體組成"
                    )
                    
                    AdvancedFeature(
                        icon: "trophy.fill",
                        title: "個人記錄",
                        description: "自動追蹤您的 1RM（單次最大重量）進步情況"
                    )
                }
                
                Divider()
                
                // 小技巧
                TutorialSection(
                    title: "實用技巧",
                    icon: "lightbulb.fill",
                    iconColor: .yellow
                ) {
                    TipCard(
                        icon: "bolt.fill",
                        title: "快速輸入",
                        description: "訓練時可以參考上一組的重量和次數，快速完成輸入"
                    )
                    
                    TipCard(
                        icon: "timer",
                        title: "休息計時",
                        description: "記錄每組後會自動開始休息計時，確保充分恢復"
                    )
                    
                    TipCard(
                        icon: "chart.bar.fill",
                        title: "訓練容量",
                        description: "訓練容量 = 重量 × 次數，是衡量訓練量的重要指標"
                    )
                    
                    TipCard(
                        icon: "magnifyingglass",
                        title: "智能搜尋",
                        description: "動作庫支援中英文搜尋，還能根據肌群篩選"
                    )
                }
                
                Divider()
                
                // 常見問題
                TutorialSection(
                    title: "常見問題",
                    icon: "questionmark.circle.fill",
                    iconColor: .green
                ) {
                    FAQCard(
                        question: "如何修改已記錄的組數？",
                        answer: "在訓練頁面，向左滑動組數記錄，可以選擇編輯或刪除"
                    )
                    
                    FAQCard(
                        question: "如何查看進步情況？",
                        answer: "前往「數據」頁面，可以查看訓練容量趨勢和個人記錄"
                    )
                }
                
                // 底部說明
                VStack(spacing: 12) {
                    Text("需要更多協助？")
                        .font(.headline)
                    
                    Text("如有任何問題或建議，歡迎透過 App Store 評價或聯絡我們")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
            }
            .padding()
        }
        .navigationTitle("使用教學")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 子組件

struct TutorialSection<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(iconColor)
                
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            content
        }
    }
}

struct TutorialStep: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 32, height: 32)
                
                Text("\(number)")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct TutorialFeatureCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct AdvancedFeature: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.purple)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct TipCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.yellow)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

struct FAQCard: View {
    let question: String
    let answer: String
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(question)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if isExpanded {
                Text(answer)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

#Preview {
    NavigationStack {
        TutorialView()
    }
}
