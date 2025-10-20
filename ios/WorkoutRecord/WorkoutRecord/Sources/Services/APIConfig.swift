import Foundation

/// API 配置
struct APIConfig {
    /// Base URL
    static var baseURL: String {
        #if DEBUG
        return "http://localhost:8080"
        #else
        return "https://your-production-api.com"
        #endif
    }
    
    /// API 版本
    static let apiVersion = "v1"
    
    /// 完整 API URL
    static var apiURL: String {
        return "\(baseURL)/api/\(apiVersion)"
    }
    
    /// 請求超時時間（秒）
    static let timeoutInterval: TimeInterval = 30
}

/// API 端點
enum APIEndpoint {
    // Auth
    case login
    case profile
    case updateProfile
    
    // Body Weight
    case bodyWeights
    case createBodyWeight
    case deleteBodyWeight(String)
    
    // Exercise
    case exercises
    case exercise(String)
    case createExercise
    
    // Workout
    case workouts
    case startWorkout
    case workout(String)
    case endWorkout(String)
    case addExercise(String)
    case addSet(workoutID: String, exerciseID: String)
    
    var path: String {
        switch self {
        // Auth
        case .login:
            return "/auth/login"
        case .profile:
            return "/auth/profile"
        case .updateProfile:
            return "/auth/profile"
            
        // Body Weight
        case .bodyWeights:
            return "/body-weights"
        case .createBodyWeight:
            return "/body-weights"
        case .deleteBodyWeight(let id):
            return "/body-weights/\(id)"
            
        // Exercise
        case .exercises:
            return "/exercises"
        case .exercise(let id):
            return "/exercises/\(id)"
        case .createExercise:
            return "/exercises"
            
        // Workout
        case .workouts:
            return "/workouts"
        case .startWorkout:
            return "/workouts"
        case .workout(let id):
            return "/workouts/\(id)"
        case .endWorkout(let id):
            return "/workouts/\(id)/end"
        case .addExercise(let id):
            return "/workouts/\(id)/exercises"
        case .addSet(let workoutID, let exerciseID):
            return "/workouts/\(workoutID)/exercises/\(exerciseID)/sets"
        }
    }
    
    var url: URL? {
        return URL(string: APIConfig.apiURL + path)
    }
}

