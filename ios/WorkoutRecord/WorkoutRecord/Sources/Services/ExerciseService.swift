import Foundation
import Combine

/// 動作服務
class ExerciseService: ObservableObject {
    static let shared = ExerciseService()
    init() {}
    
    /// 列表回應
    struct ListResponse: Decodable {
        let exercises: [Exercise]
        let total: Int
    }
    
    /// 創建請求
    struct CreateRequest: Encodable {
        let name: String
        let nameEn: String?
        let category: String
        let equipment: String
        let primaryMuscles: [String]
        let secondaryMuscles: [String]?
        
        enum CodingKeys: String, CodingKey {
            case name, category, equipment
            case nameEn = "name_en"
            case primaryMuscles = "primary_muscles"
            case secondaryMuscles = "secondary_muscles"
        }
    }
    
    /// 獲取動作列表
    func getExercises(category: String? = nil, equipment: String? = nil) async throws -> [Exercise] {
        // TODO: 添加查詢參數支援
        let response: ListResponse = try await HTTPClient.shared.request(
            endpoint: .exercises
        )
        return response.exercises
    }
    
    /// 獲取動作詳情
    func getExercise(id: String) async throws -> Exercise {
        return try await HTTPClient.shared.request(
            endpoint: .exercise(id)
        )
    }
    
    /// 創建自訂動作
    func createExercise(
        name: String,
        nameEn: String? = nil,
        category: String,
        equipment: String,
        primaryMuscles: [String],
        secondaryMuscles: [String]? = nil
    ) async throws -> Exercise {
        let request = CreateRequest(
            name: name,
            nameEn: nameEn,
            category: category,
            equipment: equipment,
            primaryMuscles: primaryMuscles,
            secondaryMuscles: secondaryMuscles
        )
        
        return try await HTTPClient.shared.request(
            endpoint: .createExercise,
            method: .post,
            body: request
        )
    }
}

