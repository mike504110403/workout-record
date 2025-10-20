import Foundation

/// Utility for calculating workout volume
/// Volume = Weight × Reps (× Sets for total)
struct VolumeCalculator {
    
    /// Calculate volume for a single set
    /// - Parameters:
    ///   - weight: Weight in kg
    ///   - reps: Number of repetitions
    /// - Returns: Volume in kg
    static func calculateSetVolume(weight: Double, reps: Int) -> Double {
        return weight * Double(reps)
    }
    
    /// Calculate total volume for an exercise
    /// - Parameter sets: Array of workout sets
    /// - Returns: Total volume in kg (excluding warmup sets)
    static func calculateExerciseVolume(sets: [WorkoutSet]) -> Double {
        return sets
            .filter { !$0.isWarmup }
            .reduce(0) { $0 + $1.volume }
    }
    
    /// Calculate total volume for a workout
    /// - Parameter exercises: Array of workout exercises
    /// - Returns: Total volume in kg
    static func calculateWorkoutVolume(exercises: [WorkoutExercise]) -> Double {
        return exercises.reduce(0) { $0 + $1.totalVolume }
    }
    
    /// Calculate total sets for a workout (excluding warmup sets)
    /// - Parameter exercises: Array of workout exercises
    /// - Returns: Total number of sets
    static func calculateTotalSets(exercises: [WorkoutExercise]) -> Int {
        return exercises.reduce(0) { total, exercise in
            total + exercise.sets.filter { !$0.isWarmup }.count
        }
    }
    
    /// Format volume for display
    /// - Parameter volume: Volume in kg
    /// - Returns: Formatted string (e.g., "5,230 kg" or "5.2 噸")
    static func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            let tons = volume / 1000
            return String(format: "%.1f 噸", tons)
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            let formatted = formatter.string(from: NSNumber(value: volume)) ?? "\(Int(volume))"
            return "\(formatted) kg"
        }
    }
}

