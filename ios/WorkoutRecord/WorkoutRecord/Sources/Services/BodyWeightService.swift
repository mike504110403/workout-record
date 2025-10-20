import Foundation

/// 體重記錄服務
class BodyWeightService {
    static let shared = BodyWeightService()
    private init() {}
    
    /// 列表回應
    struct ListResponse: Decodable {
        let records: [BodyWeight]
        let total: Int
    }
    
    /// 創建請求
    struct CreateRequest: Encodable {
        let weight: Double
        let bodyFat: Double?
        let muscleMass: Double?
        let notes: String?
        let date: Date
        
        enum CodingKeys: String, CodingKey {
            case weight, date, notes
            case bodyFat = "body_fat"
            case muscleMass = "muscle_mass"
        }
    }
    
    /// 獲取體重記錄列表
    func getBodyWeights() async throws -> [BodyWeight] {
        let response: ListResponse = try await HTTPClient.shared.request(
            endpoint: .bodyWeights
        )
        return response.records
    }
    
    /// 創建體重記錄
    func createBodyWeight(
        weight: Double,
        bodyFat: Double? = nil,
        muscleMass: Double? = nil,
        notes: String? = nil,
        date: Date
    ) async throws -> BodyWeight {
        let request = CreateRequest(
            weight: weight,
            bodyFat: bodyFat,
            muscleMass: muscleMass,
            notes: notes,
            date: date
        )
        
        return try await HTTPClient.shared.request(
            endpoint: .createBodyWeight,
            method: .post,
            body: request
        )
    }
    
    /// 刪除體重記錄
    func deleteBodyWeight(id: String) async throws {
        try await HTTPClient.shared.requestWithoutData(
            endpoint: .deleteBodyWeight(id),
            method: .delete
        )
    }
}

