import Foundation
import SwiftUI
import Combine
import FirebaseFirestore

/// 版本檢查服務
@MainActor
class VersionCheckService: ObservableObject {
    static let shared = VersionCheckService()
    
    @Published var shouldForceUpdate = false
    @Published var latestVersion: String?
    @Published var updateMessage: String?
    @Published var isCheckingVersion = false
    
    private let db = Firestore.firestore()
    
    private init() {}
    
    // MARK: - 版本檢查
    
    /// 檢查版本更新
    func checkForUpdate() async {
        await MainActor.run {
            isCheckingVersion = true
        }
        
        do {
            // 獲取當前版本
            let currentVersion = getCurrentAppVersion()
            
            // 從 Firebase 獲取最新版本資訊
            let versionDoc = try await db.collection("app_config").document("version").getDocument()
            
            guard let data = versionDoc.data() else {
                print("⚠️ 無法獲取版本資訊")
                await MainActor.run {
                    isCheckingVersion = false
                }
                return
            }
            
            let latestVersion = data["latestVersion"] as? String ?? currentVersion
            let minimumVersion = data["minimumVersion"] as? String ?? currentVersion
            
            // 處理 forceUpdate：可能是 Bool 或 String
            var forceUpdate = false
            if let boolValue = data["forceUpdate"] as? Bool {
                forceUpdate = boolValue
            } else if let stringValue = data["forceUpdate"] as? String {
                forceUpdate = (stringValue.lowercased() == "true")
            }
            
            let updateMessage = data["updateMessage"] as? String ?? "發現新版本，請更新以獲得最佳體驗。"
            
            print("📱 當前版本: \(currentVersion)")
            print("🆕 最新版本: \(latestVersion)")
            print("⚠️ 最低版本: \(minimumVersion)")
            print("🔒 強制更新: \(forceUpdate)")
            
            await MainActor.run {
                self.latestVersion = latestVersion
                self.updateMessage = updateMessage
                
                // 檢查是否需要強制更新
                if forceUpdate {
                    // 如果當前版本低於最低版本，強制更新
                    if compareVersions(currentVersion, minimumVersion) < 0 {
                        self.shouldForceUpdate = true
                        print("🚨 需要強制更新")
                    }
                } else {
                    // 如果當前版本低於最新版本，建議更新（但不強制）
                    if compareVersions(currentVersion, latestVersion) < 0 {
                        self.shouldForceUpdate = false
                        print("💡 建議更新")
                    }
                }
                
                self.isCheckingVersion = false
            }
        } catch {
            print("❌ 版本檢查失敗: \(error.localizedDescription)")
            await MainActor.run {
                isCheckingVersion = false
            }
        }
    }
    
    // MARK: - 版本工具
    
    /// 獲取當前 App 版本
    func getCurrentAppVersion() -> String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "1.0.0"
    }
    
    /// 獲取當前 Build 版本
    func getCurrentBuildVersion() -> String {
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            return build
        }
        return "1"
    }
    
    /// 比較版本號
    /// - Returns: -1 if version1 < version2, 0 if equal, 1 if version1 > version2
    private func compareVersions(_ version1: String, _ version2: String) -> Int {
        let v1Components = version1.split(separator: ".").compactMap { Int($0) }
        let v2Components = version2.split(separator: ".").compactMap { Int($0) }
        
        let maxLength = max(v1Components.count, v2Components.count)
        
        for i in 0..<maxLength {
            let v1Value = i < v1Components.count ? v1Components[i] : 0
            let v2Value = i < v2Components.count ? v2Components[i] : 0
            
            if v1Value < v2Value {
                return -1
            } else if v1Value > v2Value {
                return 1
            }
        }
        
        return 0
    }
    
    // MARK: - App Store 導向
    
    /// 開啟 App Store 更新頁面
    func openAppStore() {
        // App Store ID: 6754325448
        let appStoreID = "6754325448"
        
        if let url = URL(string: "https://apps.apple.com/app/id\(appStoreID)") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        }
    }
    
    /// 開啟 App Store 評價頁面
    func openAppStoreForReview() {
        // App Store ID: 6754325448
        let appStoreID = "6754325448"
        
        if let url = URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        }
    }
}

// MARK: - 版本更新提示視圖

struct ForceUpdateView: View {
    @ObservedObject var versionService: VersionCheckService
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // 圖標
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                // 標題
                Text("需要更新")
                    .font(.title)
                    .fontWeight(.bold)
                
                // 訊息
                Text(versionService.updateMessage ?? "發現新版本，請更新以繼續使用。")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                // 版本資訊
                if let latestVersion = versionService.latestVersion {
                    VStack(spacing: 8) {
                        HStack {
                            Text("當前版本:")
                            Spacer()
                            Text(versionService.getCurrentAppVersion())
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("最新版本:")
                            Spacer()
                            Text(latestVersion)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                // 更新按鈕
                Button {
                    versionService.openAppStore()
                } label: {
                    Text("立即更新")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
            }
            .padding(32)
            .background(Color(.systemBackground))
            .cornerRadius(20)
            .shadow(radius: 20)
            .padding(40)
        }
    }
}

