import Foundation

/// 訓練服務
class WorkoutService {
    static let shared = WorkoutService()
    private init() {}
    
    /// 列表回應
    struct ListResponse: Decodable {
        let workouts: [WorkoutSummary]
        let total: Int
    }
    
    /// 開始訓練請求
    struct StartRequest: Encodable {
        let name: String?
        let startTime: Date
        
        enum CodingKeys: String, CodingKey {
            case name
            case startTime = "start_time"
        }
    }
    
    /// 結束訓練請求
    struct EndRequest: Encodable {
        let endTime: Date?
        let notes: String?
        
        enum CodingKeys: String, CodingKey {
            case notes
            case endTime = "end_time"
        }
    }
    
    /// 添加動作請求
    struct AddExerciseRequest: Encodable {
        let exerciseId: String
        let orderIndex: Int
        
        enum CodingKeys: String, CodingKey {
            case orderIndex = "order_index"
            case exerciseId = "exercise_id"
        }
    }
    
    /// 添加組數請求
    struct AddSetRequest: Encodable {
        let setNumber: Int
        let weight: Double
        let reps: Int
        let rpe: Double?
        let isWarmup: Bool
        let restTime: Int?
        let notes: String?
        
        enum CodingKeys: String, CodingKey {
            case weight, reps, rpe, notes
            case setNumber = "set_number"
            case isWarmup = "is_warmup"
            case restTime = "rest_time"
        }
    }
    
    /// 獲取訓練列表
    func getWorkouts() async throws -> [WorkoutSummary] {
        let response: ListResponse = try await HTTPClient.shared.request(
            endpoint: .workouts
        )
        return response.workouts
    }
    
    /// 開始訓練
    func startWorkout(name: String? = nil, startTime: Date = Date()) async throws -> Workout {
        let request = StartRequest(name: name, startTime: startTime)
        return try await HTTPClient.shared.request(
            endpoint: .startWorkout,
            method: .post,
            body: request
        )
    }
    
    /// 結束訓練
    func endWorkout(id: String, endTime: Date? = nil, notes: String? = nil) async throws -> Workout {
        let request = EndRequest(endTime: endTime, notes: notes)
        return try await HTTPClient.shared.request(
            endpoint: .endWorkout(id),
            method: .put,
            body: request
        )
    }
    
    /// 獲取訓練詳情
    func getWorkout(id: String) async throws -> Workout {
        return try await HTTPClient.shared.request(
            endpoint: .workout(id)
        )
    }
    
    /// 添加動作到訓練
    func addExercise(workoutId: String, exerciseId: String, orderIndex: Int) async throws -> WorkoutExercise {
        let request = AddExerciseRequest(exerciseId: exerciseId, orderIndex: orderIndex)
        return try await HTTPClient.shared.request(
            endpoint: .addExercise(workoutId),
            method: .post,
            body: request
        )
    }
    
    /// 添加組數
    func addSet(
        workoutId: String,
        exerciseId: String,
        setNumber: Int,
        weight: Double,
        reps: Int,
        rpe: Double? = nil,
        isWarmup: Bool = false,
        restTime: Int? = nil,
        notes: String? = nil
    ) async throws -> WorkoutSet {
        let request = AddSetRequest(
            setNumber: setNumber,
            weight: weight,
            reps: reps,
            rpe: rpe,
            isWarmup: isWarmup,
            restTime: restTime,
            notes: notes
        )
        
        return try await HTTPClient.shared.request(
            endpoint: .addSet(workoutID: workoutId, exerciseID: exerciseId),
            method: .post,
            body: request
        )
    }
}

