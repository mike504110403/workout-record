import Foundation
import AuthenticationServices
import SwiftUI
import Combine

/// Apple ID 強制登入服務
@MainActor
class AppleIDAuthService: NSObject, ObservableObject {
    static let shared = AppleIDAuthService()
    
    @Published var isSignedIn: Bool = false
    @Published var userID: String?
    @Published var userName: String?
    @Published var userEmail: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showLoginRequired = false
    
    private override init() {
        super.init()
        checkSignInStatus()
    }
    
    // MARK: - 登入狀態檢查
    
    /// 檢查登入狀態
    private func checkSignInStatus() {
        #if targetEnvironment(simulator)
        // 模擬器模式：檢查是否有測試用戶
        if let userID = UserDefaults.standard.string(forKey: "AppleIDUserID"),
           let userName = UserDefaults.standard.string(forKey: "AppleIDUserName"),
           let userEmail = UserDefaults.standard.string(forKey: "AppleIDUserEmail") {
            
            self.userID = userID
            self.userName = userName
            self.userEmail = userEmail
            self.isSignedIn = true
            self.showLoginRequired = false
        } else {
            // 模擬器模式：自動創建測試用戶
            self.createTestUser()
        }
        #else
        // 真實設備：檢查是否有儲存的用戶資訊
        if let userID = UserDefaults.standard.string(forKey: "AppleIDUserID"),
           let userName = UserDefaults.standard.string(forKey: "AppleIDUserName"),
           let userEmail = UserDefaults.standard.string(forKey: "AppleIDUserEmail") {
            
            self.userID = userID
            self.userName = userName
            self.userEmail = userEmail
            self.isSignedIn = true
            self.showLoginRequired = false
        } else {
            self.isSignedIn = false
            self.showLoginRequired = true
        }
        #endif
    }
    
    #if targetEnvironment(simulator)
    /// 創建測試用戶（僅模擬器）
    private func createTestUser() {
        let testUserID = "simulator.test.user.12345"
        let testUserName = "測試用戶"
        let testUserEmail = "test@example.com"
        
        // 儲存測試用戶資訊
        UserDefaults.standard.set(testUserID, forKey: "AppleIDUserID")
        UserDefaults.standard.set(testUserName, forKey: "AppleIDUserName")
        UserDefaults.standard.set(testUserEmail, forKey: "AppleIDUserEmail")
        
        // 更新狀態
        self.userID = testUserID
        self.userName = testUserName
        self.userEmail = testUserEmail
        self.isSignedIn = true
        self.showLoginRequired = false
        
        print("✅ 模擬器模式：已創建測試用戶")
    }
    #endif
    
    // MARK: - Apple ID 登入
    
    /// 開始 Apple ID 登入
    func signInWithApple() {
        isLoading = true
        errorMessage = nil
        
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
    }
    
    /// 登出
    func signOut() {
        // 清除儲存的用戶資訊
        UserDefaults.standard.removeObject(forKey: "AppleIDUserID")
        UserDefaults.standard.removeObject(forKey: "AppleIDUserName")
        UserDefaults.standard.removeObject(forKey: "AppleIDUserEmail")
        
        // 重置狀態
        isSignedIn = false
        userID = nil
        userName = nil
        userEmail = nil
        showLoginRequired = true
    }
    
    /// 檢查 Apple ID 憑證狀態
    func checkCredentialState() {
        guard let userID = userID else { return }
        
        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: userID) { [weak self] credentialState, error in
            DispatchQueue.main.async {
                switch credentialState {
                case .authorized:
                    // 憑證有效
                    break
                case .revoked:
                    // 憑證被撤銷，需要重新登入
                    self?.signOut()
                case .notFound:
                    // 找不到憑證，需要重新登入
                    self?.signOut()
                default:
                    break
                }
            }
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleIDAuthService: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            let userID = appleIDCredential.user
            let fullName = appleIDCredential.fullName
            let email = appleIDCredential.email
            
            // 處理用戶資訊
            let userName = fullName?.formatted() ?? "用戶"
            let userEmail = email ?? "未提供電子郵件"
            
            // 儲存用戶資訊
            UserDefaults.standard.set(userID, forKey: "AppleIDUserID")
            UserDefaults.standard.set(userName, forKey: "AppleIDUserName")
            UserDefaults.standard.set(userEmail, forKey: "AppleIDUserEmail")
            
            // 更新狀態
            self.userID = userID
            self.userName = userName
            self.userEmail = userEmail
            self.isSignedIn = true
            self.showLoginRequired = false
            self.isLoading = false
            self.errorMessage = nil
            
            print("✅ Apple ID 登入成功: \(userName)")
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        isLoading = false
        errorMessage = "Apple ID 登入失敗: \(error.localizedDescription)"
        print("❌ Apple ID 登入失敗: \(error.localizedDescription)")
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleIDAuthService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return window
        }
        // 使用新的初始化方法
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return ASPresentationAnchor(windowScene: windowScene)
        }
        return ASPresentationAnchor()
    }
}
