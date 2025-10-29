import SwiftUI
import CloudKit

/// CloudKit 設定視圖
struct CloudKitSettingsView: View {
    @StateObject private var authService = AuthService.shared
    @StateObject private var cloudKitAuth = CloudKitAuthService.shared
    @StateObject private var cloudKitSync = CloudKitSyncService.shared
    
    @State private var showingSignIn = false
    @State private var showingSyncAlert = false
    
    var body: some View {
        NavigationView {
            List {
                // 登入狀態區塊
                Section {
                    if cloudKitAuth.isSignedIn {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading) {
                                Text("已登入 iCloud")
                                    .font(.headline)
                                if let userName = cloudKitAuth.userName {
                                    Text(userName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button("登出") {
                                cloudKitAuth.signOut()
                            }
                            .foregroundColor(.red)
                        }
                    } else {
                        HStack {
                            Image(systemName: "icloud.slash")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading) {
                                Text("未登入 iCloud")
                                    .font(.headline)
                                Text("登入以啟用數據同步")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("登入") {
                                cloudKitAuth.signInWithApple()
                            }
                            .foregroundColor(.blue)
                        }
                    }
                } header: {
                    Text("iCloud 帳戶")
                }
                
                // 同步設定區塊
                if cloudKitAuth.isSignedIn {
                    Section {
                        Toggle("啟用數據同步", isOn: $authService.isCloudKitEnabled)
                            .onChange(of: authService.isCloudKitEnabled) { enabled in
                                if enabled {
                                    authService.enableCloudKitSync()
                                } else {
                                    authService.disableCloudKitSync()
                                }
                            }
                        
                        if authService.isCloudKitEnabled {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("同步狀態")
                                        .font(.headline)
                                    Spacer()
                                    if cloudKitSync.isSyncing {
                                        SwiftUI.ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                }
                                
                                if cloudKitSync.isSyncing {
                                    ProgressView(value: cloudKitSync.syncProgress)
                                        .progressViewStyle(LinearProgressViewStyle())
                                }
                                
                                if let lastSync = cloudKitSync.lastSyncDate {
                                    Text("上次同步：\(lastSync, style: .relative)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                if let error = cloudKitSync.syncError {
                                    Text("同步錯誤：\(error)")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.vertical, 4)
                            
                            Button("手動同步") {
                                Task {
                                    await authService.syncData()
                                }
                            }
                            .disabled(cloudKitSync.isSyncing)
                        }
                    } header: {
                        Text("數據同步")
                    } footer: {
                        Text("啟用後，您的訓練數據將自動同步到 iCloud，並在所有設備間保持同步。")
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
                        
                        Text("• 所有數據均加密儲存在您的 iCloud 帳戶中")
                        Text("• 只有您能存取這些數據")
                        Text("• 我們無法查看您的個人數據")
                        Text("• 您可以隨時停用同步功能")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                } header: {
                    Text("隱私說明")
                }
                
                // 錯誤訊息
                if let error = cloudKitAuth.errorMessage {
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
            }
            .navigationTitle("iCloud 同步")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            cloudKitAuth.checkAccountStatus()
        }
        .trackPageView("CloudKitSettings")
    }
}

#Preview {
    CloudKitSettingsView()
}
