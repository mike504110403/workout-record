import Foundation
import Combine

@MainActor
class WorkoutViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isWorkoutInProgress = false
    @Published var currentWorkoutExercises: [WorkoutExerciseViewModel] = []
    @Published var totalVolume: Double = 0
    @Published var totalSets: Int = 0
    @Published var workoutDuration: String = "00:00"
    
    // MARK: - Private Properties
    private var workoutStartTime: Date?
    private var timerCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Public Methods
    func startWorkout() {
        isWorkoutInProgress = true
        workoutStartTime = Date()
        startTimer()
        
        // Load mock exercises for demo
        loadMockWorkout()
    }
    
    func startWorkoutFromTemplate(_ template: TemplateInfo) {
        isWorkoutInProgress = true
        workoutStartTime = Date()
        startTimer()
        
        // Load exercises from template
        currentWorkoutExercises = template.exercises.map { exercise in
            WorkoutExerciseViewModel(
                id: UUID(),
                exerciseId: UUID(), // In real app, this would be the actual exercise ID
                exerciseName: exercise.name,
                sets: []
            )
        }
        
        updateTotals()
    }
    
    func completeWorkout() {
        stopTimer()
        // TODO: Save workout to repository
        resetWorkout()
    }
    
    func cancelWorkout() {
        stopTimer()
        // TODO: Show confirmation dialog
        resetWorkout()
    }
    
    func addSet(to exercise: WorkoutExerciseViewModel, weight: Double, reps: Int, rpe: Double?) {
        let newSet = WorkoutSetViewModel(
            id: UUID(),
            setNumber: exercise.sets.count + 1,
            weight: weight,
            reps: reps,
            volume: weight * Double(reps),
            rpe: rpe,
            isWarmup: false
        )
        
        if let index = currentWorkoutExercises.firstIndex(where: { $0.id == exercise.id }) {
            currentWorkoutExercises[index].sets.append(newSet)
            updateTotals()
        }
    }
    
    func addExercise(_ exercise: Exercise) {
        let newExercise = WorkoutExerciseViewModel(
            id: UUID(),
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            sets: []
        )
        
        currentWorkoutExercises.append(newExercise)
    }
    
    func deleteSet(_ set: WorkoutSetViewModel, from exercise: WorkoutExerciseViewModel) {
        if let exerciseIndex = currentWorkoutExercises.firstIndex(where: { $0.id == exercise.id }) {
            currentWorkoutExercises[exerciseIndex].sets.removeAll { $0.id == set.id }
            
            // Renumber sets
            for (index, _) in currentWorkoutExercises[exerciseIndex].sets.enumerated() {
                currentWorkoutExercises[exerciseIndex].sets[index].setNumber = index + 1
            }
            
            updateTotals()
        }
    }
    
    // MARK: - Private Methods
    private func startTimer() {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateDuration()
            }
    }
    
    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
    
    private func updateDuration() {
        guard let startTime = workoutStartTime else { return }
        let duration = Date().timeIntervalSince(startTime)
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        workoutDuration = String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func updateTotals() {
        totalVolume = currentWorkoutExercises.reduce(0) { $0 + $1.totalVolume }
        totalSets = currentWorkoutExercises.reduce(0) { $0 + $1.sets.filter { !$0.isWarmup }.count }
    }
    
    private func resetWorkout() {
        isWorkoutInProgress = false
        currentWorkoutExercises = []
        totalVolume = 0
        totalSets = 0
        workoutDuration = "00:00"
        workoutStartTime = nil
    }
    
    private func loadMockWorkout() {
        // Mock workout with 2 exercises
        currentWorkoutExercises = [
            WorkoutExerciseViewModel(
                id: UUID(),
                exerciseId: UUID(),
                exerciseName: "槓鈴臥推",
                sets: [
                    WorkoutSetViewModel(id: UUID(), setNumber: 1, weight: 80, reps: 12, volume: 960, isWarmup: false),
                    WorkoutSetViewModel(id: UUID(), setNumber: 2, weight: 100, reps: 10, volume: 1000, isWarmup: false),
                    WorkoutSetViewModel(id: UUID(), setNumber: 3, weight: 100, reps: 8, volume: 800, isWarmup: false),
                ]
            ),
            WorkoutExerciseViewModel(
                id: UUID(),
                exerciseId: UUID(),
                exerciseName: "上斜啞鈴臥推",
                sets: [
                    WorkoutSetViewModel(id: UUID(), setNumber: 1, weight: 30, reps: 12, volume: 360, isWarmup: false),
                    WorkoutSetViewModel(id: UUID(), setNumber: 2, weight: 35, reps: 10, volume: 350, isWarmup: false),
                ]
            )
        ]
        
        updateTotals()
    }
}

// MARK: - Supporting View Models

class WorkoutExerciseViewModel: Identifiable, ObservableObject {
    let id: UUID
    let exerciseId: UUID
    let exerciseName: String
    @Published var sets: [WorkoutSetViewModel]
    
    var totalVolume: Double {
        sets.filter { !$0.isWarmup }.reduce(0) { $0 + $1.volume }
    }
    
    init(id: UUID, exerciseId: UUID, exerciseName: String, sets: [WorkoutSetViewModel]) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.sets = sets
    }
}

struct WorkoutSetViewModel: Identifiable {
    let id: UUID
    var setNumber: Int
    var weight: Double
    var reps: Int
    var volume: Double
    var rpe: Double?
    var isWarmup: Bool
    
    init(id: UUID, setNumber: Int, weight: Double, reps: Int, volume: Double, rpe: Double? = nil, isWarmup: Bool) {
        self.id = id
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.volume = volume
        self.rpe = rpe
        self.isWarmup = isWarmup
    }
}

