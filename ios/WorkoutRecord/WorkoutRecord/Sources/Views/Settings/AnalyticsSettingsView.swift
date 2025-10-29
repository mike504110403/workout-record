import SwiftUI

/// 分析設定視圖
struct AnalyticsSettingsView: View {
    @StateObject private var analyticsService = LocalAnalyticsService.shared
    @State private var showingUploadAlert = false
    @State private var showingClearDataAlert = false
    
    var body: some View {
        NavigationView {
            List {
                // 分析狀態區塊
                Section {
                    HStack {
                        Image(systemName: analyticsService.isUploading ? "arrow.up.circle.fill" : "checkmark.circle.fill")
                            .foregroundColor(analyticsService.isUploading ? .blue : .green)
                        
                        VStack(alignment: .leading) {
                            Text(analyticsService.isUploading ? "正在上傳分析數據" : "分析數據已準備就緒")
                                .font(.headline)
                            
                            if analyticsService.isUploading {
                                ProgressView(value: analyticsService.uploadProgress)
                                    .progressViewStyle(LinearProgressViewStyle())
                            }
                            
                            if let lastUpload = analyticsService.lastUploadDate {
                                Text("上次上傳：\(lastUpload, style: .relative)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("分析狀態")
                }
                
                // 上傳控制區塊
                Section {
                    Button("立即上傳分析數據") {
                        showingUploadAlert = true
                    }
                    .disabled(analyticsService.isUploading)
                    
                    Button("清除本地分析數據") {
                        showingClearDataAlert = true
                    }
                    .foregroundColor(.red)
                } header: {
                    Text("數據管理")
                } footer: {
                    Text("分析數據會定期自動上傳，您也可以手動上傳或清除本地數據。")
                }
                
                // 錯誤訊息
                if let error = analyticsService.uploadError {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .foregroundColor(.red)
                        }
                    } header: {
                        Text("錯誤")
                    }
                }
                
                // 隱私說明區塊
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(.blue)
                            Text("隱私保護")
                                .font(.headline)
                        }
                        
                        Text("• 分析數據僅用於改善 App 體驗")
                        Text("• 不包含個人識別資訊")
                        Text("• 數據加密儲存和傳輸")
                        Text("• 您可以隨時清除本地數據")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                } header: {
                    Text("隱私說明")
                }
                
                // 分析功能說明
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("分析功能包括：")
                            .font(.headline)
                        
                        Text("• 頁面瀏覽統計")
                        Text("• 按鈕點擊追蹤")
                        Text("• 功能使用情況")
                        Text("• 用戶行為模式")
                        Text("• 錯誤和崩潰追蹤")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                } header: {
                    Text("分析功能")
                }
            }
            .navigationTitle("分析設定")
            .navigationBarTitleDisplayMode(.large)
            .alert("上傳分析數據", isPresented: $showingUploadAlert) {
                Button("取消", role: .cancel) { }
                Button("確認上傳") {
                    Task {
                        await analyticsService.uploadEvents()
                    }
                }
            } message: {
                Text("這將上傳所有本地儲存的分析數據。")
            }
            .alert("清除本地數據", isPresented: $showingClearDataAlert) {
                Button("取消", role: .cancel) { }
                Button("確認清除", role: .destructive) {
                    // 清除本地分析數據
                    UserDefaults.standard.removeObject(forKey: "LocalAnalyticsData")
                }
            } message: {
                Text("這將清除所有本地儲存的分析數據，此操作無法復原。")
            }
        }
    }
}

#Preview {
    AnalyticsSettingsView()
}
