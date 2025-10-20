import Foundation

/// HTTP 方法
enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

/// HTTP 客戶端
class HTTPClient {
    static let shared = HTTPClient()
    
    private let session: URLSession
    private var authToken: String?
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = APIConfig.timeoutInterval
        configuration.timeoutIntervalForResource = APIConfig.timeoutInterval
        self.session = URLSession(configuration: configuration)
    }
    
    /// 設定認證 Token
    func setAuthToken(_ token: String?) {
        self.authToken = token
    }
    
    /// 發送請求
    func request<T: Decodable>(
        endpoint: APIEndpoint,
        method: HTTPMethod = .get,
        body: Encodable? = nil
    ) async throws -> T {
        guard let url = endpoint.url else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 添加認證 Token
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // 添加請求 body
        if let body = body {
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw APIError.decodingError(error)
            }
        }
        
        // 發送請求
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            // 檢查狀態碼
            guard (200...299).contains(httpResponse.statusCode) else {
                // 嘗試解析錯誤訊息
                if let errorResponse = try? JSONDecoder().decode(APIResponse<String>.self, from: data) {
                    throw APIError.httpError(httpResponse.statusCode, errorResponse.message)
                }
                throw APIError.httpError(httpResponse.statusCode, "請求失敗")
            }
            
            // 解析回應
            do {
                let apiResponse = try JSONDecoder().decode(APIResponse<T>.self, from: data)
                
                guard let data = apiResponse.data else {
                    throw APIError.invalidResponse
                }
                
                return data
            } catch {
                throw APIError.decodingError(error)
            }
            
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }
    
    /// 發送不需要回應資料的請求
    func requestWithoutData(
        endpoint: APIEndpoint,
        method: HTTPMethod = .get,
        body: Encodable? = nil
    ) async throws {
        let _: EmptyResponse = try await request(endpoint: endpoint, method: method, body: body)
    }
}

/// 空回應（用於不需要資料的請求）
private struct EmptyResponse: Decodable {}

