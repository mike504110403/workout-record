import SwiftUI

/// 隱私政策視圖
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 標題
                VStack(alignment: .leading, spacing: 8) {
                    Text("隱私政策")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("最後更新：2023年12月21日")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 20)
                
                // 數據收集說明
                VStack(alignment: .leading, spacing: 12) {
                    Text("我們收集的數據")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("為了改善 App 體驗和提供更好的服務，我們會收集以下類型的數據：")
                        .font(.body)
                    
                    Text("注意：我們只收集操作數據和設備資訊，不會收集您的個人訓練數據。")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.vertical, 8)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("使用數據：App 使用時長、頁面瀏覽記錄、功能使用情況")
                        }
                        
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("互動數據：按鈕點擊、手勢操作、表單填寫")
                        }
                        
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("訓練數據：訓練記錄、體重數據、個人目標設定")
                        }
                        
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("設備數據：設備型號、系統版本、App 版本")
                        }
                        
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("錯誤數據：App 崩潰報告、錯誤日誌")
                        }
                        
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("雲端同步：iCloud 和 Firebase 數據同步")
                        }
                    }
                    .font(.body)
                    .padding(.leading, 16)
                }
                
                // 數據用途說明
                VStack(alignment: .leading, spacing: 12) {
                    Text("數據用途")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("我們收集的數據僅用於以下目的：")
                        .font(.body)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("改善 App 功能和用戶體驗")
                        }
                        
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("分析用戶行為模式，優化 App 設計")
                        }
                        
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("修復錯誤和提升 App 穩定性")
                        }
                        
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("提供個性化的訓練建議")
                        }
                    }
                    .font(.body)
                    .padding(.leading, 16)
                }
                
                // 數據儲存說明
                VStack(alignment: .leading, spacing: 12) {
                    Text("數據儲存")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("我們採用以下方式保護您的數據：")
                        .font(.body)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("本地加密儲存：所有數據在您的設備上加密儲存")
                        }
                        
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("iCloud 同步：可選的雲端同步，數據加密傳輸")
                        }
                        
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("定期清理：本地分析數據每 30 天自動清理")
                        }
                        
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("匿名化處理：上傳的分析數據不包含個人識別資訊")
                        }
                        
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("Firebase 分析：使用 Google Firebase 進行數據分析")
                        }
                        
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("數據加密：所有傳輸數據使用 HTTPS 加密")
                        }
                    }
                    .font(.body)
                    .padding(.leading, 16)
                }
                
                // 數據分享說明
                VStack(alignment: .leading, spacing: 12) {
                    Text("數據分享")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("我們承諾：")
                        .font(.body)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("不會向第三方分享您的個人數據")
                        }
                        
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("不會將數據用於廣告投放")
                        }
                        
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("不會將數據出售給任何公司")
                        }
                        
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("分析數據僅用於改善 App 體驗")
                        }
                    }
                    .font(.body)
                    .padding(.leading, 16)
                }
                
                // 用戶權利
                VStack(alignment: .leading, spacing: 12) {
                    Text("您的權利")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("您擁有以下權利：")
                        .font(.body)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("隨時查看和修改您的個人資料")
                        }
                        
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("清除本地分析數據")
                        }
                        
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("停用數據收集功能")
                        }
                        
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("刪除您的帳戶和所有相關數據")
                        }
                    }
                    .font(.body)
                    .padding(.leading, 16)
                }
                
                // 聯繫方式
                VStack(alignment: .leading, spacing: 12) {
                    Text("聯繫我們")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("如果您對隱私政策有任何疑問，請聯繫我們：")
                        .font(.body)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("電子郵件：mike504110403@gmail.com")
                        }
                        
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("App 內設定：設定 → 關於 → 聯繫我們")
                        }
                    }
                    .font(.body)
                    .padding(.leading, 16)
                }
            }
            .padding()
        }
        .navigationTitle("隱私政策")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationView {
        PrivacyPolicyView()
    }
}
