import Foundation
import CloudKit
import AuthenticationServices
import SwiftUI
import Combine

/// CloudKit 認證服務
@MainActor
class CloudKitAuthService: NSObject, ObservableObject {
    static let shared = CloudKitAuthService()
    
    @Published var isSignedIn = false
    @Published var userID: String?
    @Published var userName: String?
    @Published var userEmail: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var container: CKContainer?
    private var accountStatus: CKAccountStatus = .couldNotDetermine
    
    override init() {
        super.init()
        
        // 立即初始化 CloudKit，但使用安全的方式
        initializeCloudKit()
    }
    
    /// 安全地初始化 CloudKit
    private func initializeCloudKit() {
        isLoading = true
        errorMessage = nil
        
        // 檢查 CloudKit 權限
        guard checkCloudKitEntitlements() else {
            DispatchQueue.main.async {
                self.errorMessage = "CloudKit 權限未正確配置，請檢查 entitlements 文件"
                self.isLoading = false
            }
            return
        }
        
        // 檢查 CloudKit 是否可用
        do {
            self.container = CKContainer.default()
            print("✅ CloudKit 容器初始化成功")
            
            // 延遲檢查帳戶狀態，避免啟動時的阻塞
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.checkAccountStatus()
            }
        } catch {
            print("❌ CloudKit 初始化失敗: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.errorMessage = "CloudKit 初始化失敗: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    /// 檢查 CloudKit 權限
    private func checkCloudKitEntitlements() -> Bool {
        // 檢查是否有 CloudKit 權限
        guard let path = Bundle.main.path(forResource: "WorkoutRecord", ofType: "entitlements"),
              let data = NSData(contentsOfFile: path),
              let plist = try? PropertyListSerialization.propertyList(from: data as Data, options: [], format: nil) as? [String: Any],
              let iCloudServices = plist["com.apple.developer.icloud-services"] as? [String],
              iCloudServices.contains("CloudKit") else {
            print("❌ CloudKit 權限未正確配置")
            return false
        }
        print("✅ CloudKit 權限配置正確")
        return true
    }
    
    // MARK: - 帳戶狀態檢查
    
    /// 檢查 iCloud 帳戶狀態
    func checkAccountStatus() {
        guard let container = container else {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "CloudKit 容器未初始化"
                self.isSignedIn = false
            }
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                accountStatus = try await container.accountStatus()
                await MainActor.run {
                    isLoading = false
                    updateSignInStatus()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "檢查帳戶狀態失敗: \(error.localizedDescription)"
                    print("❌ CloudKit 帳戶狀態檢查失敗: \(error.localizedDescription)")
                    
                    // 如果是網路錯誤，提供重試選項
                    if error.localizedDescription.contains("network") {
                        self.errorMessage = "網路連接失敗，請檢查網路設定後重試"
                    }
                }
            }
        }
    }
    
    /// 重試 CloudKit 初始化
    func retryInitialization() {
        print("🔄 重試 CloudKit 初始化...")
        initializeCloudKit()
    }
    
    /// 更新登入狀態
    private func updateSignInStatus() {
        isSignedIn = (accountStatus == .available)
        
        if isSignedIn {
            loadUserInfo()
        } else {
            userID = nil
            userName = nil
            userEmail = nil
        }
    }
    
    // MARK: - Apple ID 登入
    
    /// 使用 Apple ID 登入
    func signInWithApple() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
    }
    
    /// 登出
    func signOut() {
        // CloudKit 登出（實際上只是清除本地狀態）
        isSignedIn = false
        userID = nil
        userName = nil
        userEmail = nil
        errorMessage = nil
        
        // 清除本地儲存的認證資訊
        UserDefaults.standard.removeObject(forKey: "CloudKitUserID")
        UserDefaults.standard.removeObject(forKey: "CloudKitUserName")
        UserDefaults.standard.removeObject(forKey: "CloudKitUserEmail")
    }
    
    // MARK: - 用戶資訊管理
    
    /// 載入用戶資訊
    private func loadUserInfo() {
        guard let container = container else {
            DispatchQueue.main.async {
                self.errorMessage = "CloudKit 容器未初始化"
            }
            return
        }
        
        Task {
            do {
                let userRecord = try await container.userRecordID()
                let userID = userRecord.recordName
                
                // 嘗試從 CloudKit 獲取用戶詳細資訊
                // 注意：userIdentity 在 iOS 17.0 中已棄用
                // let userInfo = try await container.userIdentity(forEmailAddress: "")
                let userInfo: CKUserIdentity? = nil
                
                await MainActor.run {
                    self.userID = userID
                    self.userName = userInfo?.nameComponents?.formatted() ?? "用戶"
                    self.userEmail = userInfo?.lookupInfo?.emailAddress
                    
                    // 儲存到本地
                    UserDefaults.standard.set(userID, forKey: "CloudKitUserID")
                    if let name = self.userName {
                        UserDefaults.standard.set(name, forKey: "CloudKitUserName")
                    }
                    if let email = self.userEmail {
                        UserDefaults.standard.set(email, forKey: "CloudKitUserEmail")
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "載入用戶資訊失敗: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - CloudKit 數據同步
    
    /// 同步用戶設定到 CloudKit
    func syncUserSettings() async throws {
        guard isSignedIn, let userID = userID else {
            throw CloudKitError.notSignedIn
        }
        
        let profile = UserProfile.shared
        let record = CKRecord(recordType: "UserProfile", recordID: CKRecord.ID(recordName: userID))
        
        record["name"] = profile.name
        record["email"] = profile.email
        record["gender"] = profile.gender
        record["age"] = profile.age
        record["height"] = profile.height
        record["currentWeight"] = profile.currentWeight
        record["targetWeight"] = profile.targetWeight
        record["weeklyGoal"] = profile.weeklyGoal
        record["lastSyncDate"] = Date()
        
        guard let container = container else {
            throw CloudKitError.unknown
        }
        try await container.privateCloudDatabase.save(record)
    }
    
    /// 從 CloudKit 載入用戶設定
    func loadUserSettings() async throws {
        guard isSignedIn, let userID = userID else {
            throw CloudKitError.notSignedIn
        }
        
        let recordID = CKRecord.ID(recordName: userID)
        guard let container = container else {
            throw CloudKitError.unknown
        }
        let record = try await container.privateCloudDatabase.record(for: recordID)
        
        let profile = UserProfile.shared
        profile.name = record["name"] as? String ?? ""
        profile.email = record["email"] as? String ?? ""
        profile.gender = record["gender"] as? String ?? "不指定"
        profile.age = record["age"] as? Int ?? 0
        profile.height = record["height"] as? Double ?? 0
        profile.currentWeight = record["currentWeight"] as? Double ?? 0
        profile.targetWeight = record["targetWeight"] as? Double ?? 0
        profile.weeklyGoal = record["weeklyGoal"] as? Int ?? 4
        
        profile.save()
    }
    
    // MARK: - 錯誤處理
}

// MARK: - ASAuthorizationControllerDelegate

extension CloudKitAuthService: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            let userID = appleIDCredential.user
            let fullName = appleIDCredential.fullName
            let email = appleIDCredential.email
            
            Task {
                await MainActor.run {
                    self.userID = userID
                    self.userName = fullName?.formatted() ?? "用戶"
                    self.userEmail = email
                    self.isSignedIn = true
                    self.errorMessage = nil
                    
                    // 儲存到本地
                    UserDefaults.standard.set(userID, forKey: "CloudKitUserID")
                    if let name = self.userName {
                        UserDefaults.standard.set(name, forKey: "CloudKitUserName")
                    }
                    if let email = self.userEmail {
                        UserDefaults.standard.set(email, forKey: "CloudKitUserEmail")
                    }
                }
                
                // 同步用戶設定到 CloudKit
                do {
                    try await syncUserSettings()
                } catch {
                    await MainActor.run {
                        self.errorMessage = "同步設定失敗: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task {
            await MainActor.run {
                self.errorMessage = "Apple ID 登入失敗: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
}

// MARK: - CloudKit 錯誤定義

enum CloudKitError: Error {
    case notSignedIn
    case networkError
    case unknown
    case containerNotInitialized
    case syncFailed(String)
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension CloudKitAuthService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return window
        }
        return ASPresentationAnchor()
    }
}
