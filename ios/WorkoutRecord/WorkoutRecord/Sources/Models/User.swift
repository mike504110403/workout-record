import Foundation

struct User: Identifiable, Codable {
    let id: UUID
    var email: String
    var name: String?
    var avatarURL: String?
    var height: Double?
    var gender: Gender?
    var birthDate: Date?
    var targetWeight: Double?
    var weeklyWorkoutGoal: Int?
    var preferredUnit: WeightUnit
    var preferred1RMFormula: OneRMFormula
    let createdAt: Date
    var updatedAt: Date
    
    enum Gender: String, Codable {
        case male = "male"
        case female = "female"
        case other = "other"
    }
    
    enum WeightUnit: String, Codable, CaseIterable {
        case kg = "kg"
        case lb = "lb"
        
        var displayName: String {
            switch self {
            case .kg: return "公斤"
            case .lb: return "磅"
            }
        }
    }
    
    enum OneRMFormula: String, Codable, CaseIterable {
        case epley = "epley"
        case brzycki = "brzycki"
        case lander = "lander"
        
        var displayName: String {
            switch self {
            case .epley: return "Epley"
            case .brzycki: return "Brzycki"
            case .lander: return "Lander"
            }
        }
        
        /// Calculate 1RM based on weight and reps
        func calculate(weight: Double, reps: Int) -> Double {
            switch self {
            case .epley:
                return weight * (1 + Double(reps) / 30.0)
            case .brzycki:
                return weight * (36.0 / (37.0 - Double(reps)))
            case .lander:
                return weight * (100.0 / (101.3 - 2.67123 * Double(reps)))
            }
        }
    }
    
    init(
        id: UUID = UUID(),
        email: String,
        name: String? = nil,
        avatarURL: String? = nil,
        height: Double? = nil,
        gender: Gender? = nil,
        birthDate: Date? = nil,
        targetWeight: Double? = nil,
        weeklyWorkoutGoal: Int? = nil,
        preferredUnit: WeightUnit = .kg,
        preferred1RMFormula: OneRMFormula = .epley,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.avatarURL = avatarURL
        self.height = height
        self.gender = gender
        self.birthDate = birthDate
        self.targetWeight = targetWeight
        self.weeklyWorkoutGoal = weeklyWorkoutGoal
        self.preferredUnit = preferredUnit
        self.preferred1RMFormula = preferred1RMFormula
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

