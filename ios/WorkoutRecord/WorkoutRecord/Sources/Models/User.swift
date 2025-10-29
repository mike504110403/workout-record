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
    
    // MARK: - 新增偏好設定欄位
    var defaultRestTime: Int = 90
    var showVolumeInStats: Bool = true
    var enableHapticFeedback: Bool = true
    var autoSaveWorkout: Bool = true
    var theme: AppTheme = .system
    var enableNotifications: Bool = true
    var notificationTime: String = "20:00"
    var language: String = "zh-TW"
    
    // MARK: - Apple ID 相關欄位
    var appleID: String?
    var appleIDEmail: String?
    var appleIDName: String?
    
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
        
        var symbol: String {
            switch self {
            case .kg: return "kg"
            case .lb: return "lb"
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
    
    enum AppTheme: String, Codable, CaseIterable {
        case light = "light"
        case dark = "dark"
        case system = "system"
        
        var displayName: String {
            switch self {
            case .light: return "淺色"
            case .dark: return "深色"
            case .system: return "跟隨系統"
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
        updatedAt: Date = Date(),
        defaultRestTime: Int = 90,
        showVolumeInStats: Bool = true,
        enableHapticFeedback: Bool = true,
        autoSaveWorkout: Bool = true,
        theme: AppTheme = .system,
        enableNotifications: Bool = true,
        notificationTime: String = "20:00",
        language: String = "zh-TW",
        appleID: String? = nil,
        appleIDEmail: String? = nil,
        appleIDName: String? = nil
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
        self.defaultRestTime = defaultRestTime
        self.showVolumeInStats = showVolumeInStats
        self.enableHapticFeedback = enableHapticFeedback
        self.autoSaveWorkout = autoSaveWorkout
        self.theme = theme
        self.enableNotifications = enableNotifications
        self.notificationTime = notificationTime
        self.language = language
        self.appleID = appleID
        self.appleIDEmail = appleIDEmail
        self.appleIDName = appleIDName
    }
}

