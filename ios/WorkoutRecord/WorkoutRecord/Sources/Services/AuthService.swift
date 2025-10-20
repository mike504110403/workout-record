import Foundation

/// 認證服務
class AuthService {
    static let shared = AuthService()
    private init() {}
    
    /// 登入請求
    struct LoginRequest: Encodable {
        let provider: String
        let token: String
    }
    
    /// 登入回應
    struct LoginResponse: Decodable {
        let token: String
        let user: User
    }
    
    /// 登入
    func login(provider: String, token: String) async throws -> LoginResponse {
        let request = LoginRequest(provider: provider, token: token)
        let response: LoginResponse = try await HTTPClient.shared.request(
            endpoint: .login,
            method: .post,
            body: request
        )
        
        // 儲存 token
        HTTPClient.shared.setAuthToken(response.token)
        
        return response
    }
    
    /// 獲取個人資料
    func getProfile() async throws -> User {
        return try await HTTPClient.shared.request(endpoint: .profile)
    }
    
    /// 更新個人資料
    func updateProfile(
        name: String? = nil,
        height: Double? = nil,
        targetWeight: Double? = nil,
        weeklyGoal: Int? = nil
    ) async throws -> User {
        struct UpdateRequest: Encodable {
            let name: String?
            let height: Double?
            let target_weight: Double?
            let weekly_goal: Int?
            
            enum CodingKeys: String, CodingKey {
                case name, height
                case target_weight = "target_weight"
                case weekly_goal = "weekly_goal"
            }
        }
        
        let request = UpdateRequest(
            name: name,
            height: height,
            target_weight: targetWeight,
            weekly_goal: weeklyGoal
        )
        
        return try await HTTPClient.shared.request(
            endpoint: .updateProfile,
            method: .put,
            body: request
        )
    }
}

