import Foundation
import Combine

@MainActor
class DashboardViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var todayWorkout: WorkoutSummary?
    @Published var currentWeight: Double?
    @Published var weekWorkoutCount: Int = 0
    @Published var weekTotalVolume: Double = 0
    @Published var recentWorkouts: [WorkoutSummary] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // 目標相關
    @Published var userGoal: UserGoal?
    @Published var workoutProgress: GoalProgress?
    @Published var motivationalMessage: String = ""
    
    // MARK: - Private Properties
    private let workoutRepository = WorkoutRepository()
    private let bodyWeightRepository = BodyWeightRepository()
    private let goalRepository = UserGoalRepository()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        loadData()
    }
    
    // MARK: - Public Methods
    func refresh() {
        loadData()
    }
    
    // MARK: - Private Methods
    
    private func loadData() {
        isLoading = true
        errorMessage = nil
        
        do {
            let userId = DataMigrationService.getCurrentUserId()
            
            // 0. 獲取用戶目標（可能不存在）
            do {
                userGoal = try goalRepository.fetchByUser(userId)
            } catch {
                print("⚠️ 獲取用戶目標失敗（可能尚未設定）: \(error)")
                userGoal = nil
            }
            
            // 1. 獲取最新體重
            if let latestWeight = try bodyWeightRepository.getLatestWeight() {
                currentWeight = latestWeight.weight
            }
            
            // 2. 獲取本週統計
            let calendar = Calendar.current
            let now = Date()
            guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else {
                return
            }
            
            weekWorkoutCount = try workoutRepository.countWorkouts(from: weekStart, to: now)
            weekTotalVolume = try workoutRepository.calculateTotalVolume(from: weekStart, to: now)
            
            // 3. 獲取今天的訓練
            let startOfToday = calendar.startOfDay(for: now)
            let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
            let todayWorkouts = try workoutRepository.fetchByDateRange(from: startOfToday, to: endOfToday)
            if let firstToday = todayWorkouts.first {
                todayWorkout = convertToSummary(firstToday)
            } else {
                todayWorkout = nil
            }
            
            // 4. 獲取最近訓練
            let recentList = try workoutRepository.fetchRecent(limit: 5)
            recentWorkouts = recentList.map { convertToSummary($0) }
            
            // 5. 計算目標進度
            calculateGoalProgress()
            
            print("✅ Dashboard 數據載入完成")
        } catch {
            errorMessage = "載入數據失敗: \(error.localizedDescription)"
            print("❌ Dashboard 載入失敗: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Goal Progress
    
    private func calculateGoalProgress() {
        guard let goal = userGoal else {
            workoutProgress = nil
            motivationalMessage = "設定目標，追蹤進步！"
            return
        }
        
        // 計算訓練次數進度
        workoutProgress = GoalProgress(
            current: Double(weekWorkoutCount),
            target: Double(goal.weeklyWorkoutGoal)
        )
        
        // 生成鼓勵訊息
        motivationalMessage = generateMotivationalMessage(
            current: weekWorkoutCount,
            target: goal.weeklyWorkoutGoal
        )
    }
    
    private func generateMotivationalMessage(current: Int, target: Int) -> String {
        let percentage = target > 0 ? (Double(current) / Double(target)) * 100 : 0
        
        switch percentage {
        case 0:
            return "開始本週第一次訓練吧！💪"
        case 1..<30:
            return "不錯的開始！繼續加油💪"
        case 30..<50:
            return "穩定前進中！堅持下去🔥"
        case 50..<80:
            return "快達成目標了！再加把勁🔥"
        case 80..<100:
            return "就差一點點了！衝刺吧🚀"
        case 100:
            return "太棒了！本週目標達成✨"
        default:
            return "超越目標！你太強了🏆"
        }
    }
    
    private func convertToSummary(_ workout: Workout) -> WorkoutSummary {
        return WorkoutSummary(
            id: workout.id,
            date: workout.startedAt,
            duration: workout.duration ?? 0,
            totalVolume: workout.totalVolume,
            totalSets: workout.totalSets,
            exercisesCount: workout.totalExercises
        )
    }
    
    // MARK: - Deprecated Mock Methods (保留以備測試)
    #if DEBUG
    private func loadMockData() {
        // Mock today's workout
        todayWorkout = WorkoutSummary(
            id: UUID(),
            date: Date(),
            duration: 75,
            totalVolume: 5230,
            totalSets: 24,
            exercisesCount: 6
        )
        
        // Mock current weight
        currentWeight = 75.5
        
        // Mock this week stats
        weekWorkoutCount = 4
        weekTotalVolume = 18250
        
        // Mock recent workouts
        recentWorkouts = [
            WorkoutSummary(
                id: UUID(),
                date: Date().addingTimeInterval(-86400),
                duration: 80,
                totalVolume: 4800,
                totalSets: 22,
                exercisesCount: 5
            ),
            WorkoutSummary(
                id: UUID(),
                date: Date().addingTimeInterval(-172800),
                duration: 70,
                totalVolume: 4200,
                totalSets: 20,
                exercisesCount: 5
            ),
            WorkoutSummary(
                id: UUID(),
                date: Date().addingTimeInterval(-259200),
                duration: 85,
                totalVolume: 5020,
                totalSets: 26,
                exercisesCount: 6
            )
        ]
    }
    #endif
}

