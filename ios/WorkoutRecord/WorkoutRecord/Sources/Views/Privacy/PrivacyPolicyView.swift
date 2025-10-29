import SwiftUI

/// 專業的隱私權條款視圖
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection: PrivacySection = .overview
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 標題區域
                headerSection
                
                // 內容區域
                contentSection
            }
            .navigationTitle("隱私權政策")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("關閉") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("同意") {
                        acceptPrivacyPolicy()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            // 應用圖標和名稱
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("隱私權政策")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("健身記錄應用程式")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // 更新日期
            HStack {
                Text("最後更新：2024年1月1日")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separator)),
            alignment: .bottom
        )
    }
    
    // MARK: - Content Section
    
    private var contentSection: some View {
        HStack(spacing: 0) {
            // 側邊欄
            sidebar
            
            // 主內容
            mainContent
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(PrivacySection.allCases, id: \.self) { section in
                Button {
                    selectedSection = section
                } label: {
                    HStack {
                        Text(section.title)
                            .font(.subheadline)
                            .foregroundColor(selectedSection == section ? .primary : .secondary)
                        
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(selectedSection == section ? Color(.secondarySystemBackground) : Color.clear)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
        .frame(width: 180)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color(.separator)),
            alignment: .trailing
        )
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 章節標題
                Text(selectedSection.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.bottom, 8)
                
                // 章節內容
                sectionContent
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }
    
    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .overview:
            OverviewSection()
        case .dataCollection:
            DataCollectionSection()
        case .dataUsage:
            DataUsageSection()
        case .dataSharing:
            DataSharingSection()
        case .dataSecurity:
            DataSecuritySection()
        case .userRights:
            UserRightsSection()
        case .contact:
            ContactSection()
        }
    }
    
    // MARK: - Actions
    
    private func acceptPrivacyPolicy() {
        // 記錄用戶同意隱私權政策
        UserDefaults.standard.set(true, forKey: "PrivacyPolicyAccepted")
        UserDefaults.standard.set(Date(), forKey: "PrivacyPolicyAcceptedDate")
        
        dismiss()
    }
}

// MARK: - Privacy Sections

enum PrivacySection: String, CaseIterable {
    case overview = "overview"
    case dataCollection = "dataCollection"
    case dataUsage = "dataUsage"
    case dataSharing = "dataSharing"
    case dataSecurity = "dataSecurity"
    case userRights = "userRights"
    case contact = "contact"
    
    var title: String {
        switch self {
        case .overview: return "概述"
        case .dataCollection: return "資料收集"
        case .dataUsage: return "資料使用"
        case .dataSharing: return "資料分享"
        case .dataSecurity: return "資料安全"
        case .userRights: return "用戶權利"
        case .contact: return "聯絡我們"
        }
    }
    
    var icon: String {
        switch self {
        case .overview: return "doc.text"
        case .dataCollection: return "square.and.arrow.down"
        case .dataUsage: return "gear"
        case .dataSharing: return "square.and.arrow.up"
        case .dataSecurity: return "lock.shield"
        case .userRights: return "person.circle"
        case .contact: return "envelope"
        }
    }
}

// MARK: - Section Views

struct OverviewSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("歡迎使用健身記錄應用程式")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("我們重視您的隱私權，並致力於保護您的個人資料。本隱私權政策說明我們如何收集、使用、儲存和保護您的資訊。")
                .font(.body)
            
            VStack(alignment: .leading, spacing: 12) {
                PolicyPoint(
                    icon: "checkmark.circle.fill",
                    title: "透明原則",
                    description: "我們會清楚說明資料收集和使用方式"
                )
                
                PolicyPoint(
                    icon: "checkmark.circle.fill",
                    title: "最小化原則",
                    description: "我們只收集必要的資料"
                )
                
                PolicyPoint(
                    icon: "checkmark.circle.fill",
                    title: "安全原則",
                    description: "我們採用業界標準的安全措施"
                )
            }
        }
    }
}

struct DataCollectionSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("我們收集的資料類型")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 16) {
                DataTypeCard(
                    title: "個人資料",
                    description: "姓名、電子郵件地址（透過 Apple ID 登入）",
                    isRequired: true
                )
                
                DataTypeCard(
                    title: "訓練資料",
                    description: "訓練記錄、動作、重量、次數、組數",
                    isRequired: true
                )
                
                DataTypeCard(
                    title: "健康資料",
                    description: "體重、身高、目標設定",
                    isRequired: false
                )
                
                DataTypeCard(
                    title: "使用資料",
                    description: "應用程式使用統計、錯誤報告",
                    isRequired: false
                )
            }
        }
    }
}

struct DataUsageSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("資料使用目的")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                UsageItem(
                    text: "提供服務：記錄和管理您的訓練資料"
                )
                
                UsageItem(
                    text: "進度追蹤：分析您的訓練進度和表現"
                )
                
                UsageItem(
                    text: "成就系統：計算和解鎖各種成就"
                )
                
                UsageItem(
                    text: "資料同步：在您的設備間同步資料"
                )
                
                UsageItem(
                    text: "改善服務：優化應用程式功能和性能"
                )
            }
        }
    }
}

struct DataSharingSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("資料分享政策")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("我們不會出售、交易或轉讓您的個人資料給第三方，除非：")
                .font(.body)
            
            VStack(alignment: .leading, spacing: 12) {
                SharingItem(
                    icon: "checkmark.circle.fill",
                    title: "獲得您的同意",
                    description: "在獲得您明確同意的情況下"
                )
                
                SharingItem(
                    icon: "checkmark.circle.fill",
                    title: "法律要求",
                    description: "法律要求或法院命令"
                )
                
                SharingItem(
                    icon: "checkmark.circle.fill",
                    title: "服務提供商",
                    description: "與可信賴的服務提供商合作（如 Apple、Firebase）"
                )
            }
            
            Divider()
            
            Text("我們使用的第三方服務：")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                ThirdPartyService(
                    name: "Apple",
                    purpose: "Apple ID 登入、iCloud 同步",
                    privacyPolicy: "https://www.apple.com/privacy/"
                )
                
                ThirdPartyService(
                    name: "Firebase",
                    purpose: "資料儲存、分析",
                    privacyPolicy: "https://firebase.google.com/support/privacy"
                )
            }
        }
    }
}

struct DataSecuritySection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("資料安全措施")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                SecurityMeasure(
                    icon: "lock.fill",
                    title: "加密傳輸",
                    description: "所有資料傳輸都使用 HTTPS 加密"
                )
                
                SecurityMeasure(
                    icon: "shield.fill",
                    title: "安全儲存",
                    description: "資料儲存在安全的雲端環境中"
                )
                
                SecurityMeasure(
                    icon: "key.fill",
                    title: "存取控制",
                    description: "嚴格控制資料存取權限"
                )
                
                SecurityMeasure(
                    icon: "eye.slash.fill",
                    title: "匿名化",
                    description: "分析資料會進行匿名化處理"
                )
            }
            
            Divider()
            
            Text("資料保留政策")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Text("我們會保留您的資料直到您刪除帳戶或要求刪除。刪除後，資料將在 30 天內從我們的系統中完全移除。")
                .font(.body)
        }
    }
}

struct UserRightsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("您的權利")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("根據相關法律，您享有以下權利：")
                .font(.body)
            
            VStack(alignment: .leading, spacing: 12) {
                UserRight(
                    icon: "eye.fill",
                    title: "查閱權",
                    description: "查看我們持有的您的個人資料"
                )
                
                UserRight(
                    icon: "pencil",
                    title: "更正權",
                    description: "更正不準確的個人資料"
                )
                
                UserRight(
                    icon: "trash.fill",
                    title: "刪除權",
                    description: "要求刪除您的個人資料"
                )
                
                UserRight(
                    icon: "square.and.arrow.down",
                    title: "資料可攜權",
                    description: "以結構化格式匯出您的資料"
                )
                
                UserRight(
                    icon: "hand.raised.fill",
                    title: "反對權",
                    description: "反對處理您的個人資料"
                )
            }
            
            Divider()
            
            Text("如何行使您的權利")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Text("您可以透過應用程式內的設定頁面或聯絡我們來行使上述權利。我們會在收到請求後 30 天內回應。")
                .font(.body)
        }
    }
}

struct ContactSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("聯絡我們")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("如果您對本隱私權政策有任何疑問或建議，請透過以下方式聯絡我們：")
                .font(.body)
            
            VStack(alignment: .leading, spacing: 16) {
                ContactMethod(
                    icon: "envelope.fill",
                    title: "電子郵件",
                    value: "mike504110403@gmail.com",
                    action: "mailto:mike504110403@gmail.com"
                )
                
                ContactMethod(
                    icon: "globe",
                    title: "網站",
                    value: "https://workoutrecord.app/privacy",
                    action: "https://workoutrecord.app/privacy"
                )
            }
            
            Divider()
            
            Text("政策更新")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Text("我們可能會不時更新本隱私權政策。重大變更會透過應用程式通知您。建議您定期查看本政策以了解最新資訊。")
                .font(.body)
        }
    }
}

// MARK: - Supporting Components

struct PolicyPoint: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.primary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

struct DataTypeCard: View {
    let title: String
    let description: String
    let isRequired: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text(isRequired ? "必要" : "選填")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(isRequired ? Color.red.opacity(0.2) : Color.gray.opacity(0.2))
                    .foregroundColor(isRequired ? .red : .gray)
                    .cornerRadius(4)
            }
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

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

struct SharingItem: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.primary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

struct ThirdPartyService: View {
    let name: String
    let purpose: String
    let privacyPolicy: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(purpose)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("隱私政策") {
                if let url = URL(string: privacyPolicy) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption)
            .foregroundColor(.blue)
        }
        .padding(.vertical, 4)
    }
}

struct SecurityMeasure: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.primary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

struct UserRight: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.primary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

struct ContactMethod: View {
    let icon: String
    let title: String
    let value: String
    let action: String
    
    var body: some View {
        Button {
            if let url = URL(string: action) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(value)
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PrivacyPolicyView()
}
