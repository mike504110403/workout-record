import Foundation

struct BodyWeight: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    var weight: Double  // in kg
    let measuredAt: Date
    var note: String?
    let createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        weight: Double,
        measuredAt: Date = Date(),
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.weight = weight
        self.measuredAt = measuredAt
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Body Weight Statistics
struct BodyWeightStats: Codable {
    let current: Double?
    let average: Double
    let maximum: Double
    let minimum: Double
    let change: Double
    let changePercentage: Double
    let trend: Trend
    
    enum Trend: String, Codable {
        case increasing
        case decreasing
        case stable
    }
}

// MARK: - Body Weight Trend Point
struct BodyWeightTrendPoint: Identifiable, Codable {
    let id: UUID
    let date: Date
    let weight: Double
    
    init(id: UUID = UUID(), date: Date, weight: Double) {
        self.id = id
        self.date = date
        self.weight = weight
    }
}

