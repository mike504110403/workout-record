import SwiftUI
import AuthenticationServices

/// Apple ID 強制登入視圖
struct AppleIDLoginView: View {
    @StateObject private var authService = AppleIDAuthService.shared
    @State private var showError = false
    
    var body: some View {
        ZStack {
            // 背景
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // 標題區域
                VStack(spacing: 16) {
                    Image(systemName: "applelogo")
                        .font(.system(size: 64))
                        .foregroundColor(.primary)
                    
                    Text("歡迎使用 WorkoutRecord")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text("請使用 Apple ID 登入以開始使用")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // 登入按鈕
                VStack(spacing: 16) {
                    #if targetEnvironment(simulator)
                    // 模擬器模式：顯示測試登入按鈕
                    Button("模擬器測試登入") {
                        handleSimulatorLogin()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(height: 50)
                    .frame(maxWidth: .infinity)
                    .cornerRadius(8)
                    #else
                    // 真實設備：使用 Apple ID 登入
                    SignInWithAppleButton(
                        onRequest: { request in
                            request.requestedScopes = [.fullName, .email]
                        },
                        onCompletion: { result in
                            switch result {
                            case .success(let authorization):
                                if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                    handleAppleIDCredential(appleIDCredential)
                                }
                            case .failure(let error):
                                authService.errorMessage = "登入失敗: \(error.localizedDescription)"
                                showError = true
                            }
                        }
                    )
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .cornerRadius(8)
                    #endif
                    
                    if authService.isLoading {
                        HStack {
                            SwiftUI.ProgressView()
                                .scaleEffect(0.8)
                            Text("登入中...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // 隱私說明
                VStack(spacing: 12) {
                    Text("隱私保護")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("我們不會收集您的個人資訊")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(alignment: .top) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("所有數據僅用於改善 App 體驗")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(alignment: .top) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("您可以隨時登出")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .alert("登入錯誤", isPresented: $showError) {
            Button("確定") { }
        } message: {
            Text(authService.errorMessage ?? "未知錯誤")
        }
    }
    
    /// 處理模擬器登入
    private func handleSimulatorLogin() {
        authService.isLoading = true
        
        // 模擬登入延遲
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let testUserID = "simulator.test.user.12345"
            let testUserName = "測試用戶"
            let testUserEmail = "test@example.com"
            
            // 儲存測試用戶資訊
            UserDefaults.standard.set(testUserID, forKey: "AppleIDUserID")
            UserDefaults.standard.set(testUserName, forKey: "AppleIDUserName")
            UserDefaults.standard.set(testUserEmail, forKey: "AppleIDUserEmail")
            
            // 更新狀態
            authService.userID = testUserID
            authService.userName = testUserName
            authService.userEmail = testUserEmail
            authService.isSignedIn = true
            authService.showLoginRequired = false
            authService.isLoading = false
            authService.errorMessage = nil
            
            print("✅ 模擬器登入成功: \(testUserName)")
        }
    }
    
    /// 處理 Apple ID 憑證
    private func handleAppleIDCredential(_ credential: ASAuthorizationAppleIDCredential) {
        let userID = credential.user
        let fullName = credential.fullName
        let email = credential.email
        
        // 處理用戶資訊
        let userName = fullName?.formatted() ?? "用戶"
        let userEmail = email ?? "未提供電子郵件"
        
        // 儲存用戶資訊
        UserDefaults.standard.set(userID, forKey: "AppleIDUserID")
        UserDefaults.standard.set(userName, forKey: "AppleIDUserName")
        UserDefaults.standard.set(userEmail, forKey: "AppleIDUserEmail")
        
        // 更新狀態
        authService.userID = userID
        authService.userName = userName
        authService.userEmail = userEmail
        authService.isSignedIn = true
        authService.showLoginRequired = false
        authService.isLoading = false
        authService.errorMessage = nil
        
        print("✅ Apple ID 登入成功: \(userName)")
    }
}

#Preview {
    AppleIDLoginView()
}
