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
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        loadMockData()
    }
    
    // MARK: - Public Methods
    func refresh() {
        isLoading = true
        // TODO: Fetch real data from repository
        loadMockData()
        isLoading = false
    }
    
    // MARK: - Private Methods
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
}

