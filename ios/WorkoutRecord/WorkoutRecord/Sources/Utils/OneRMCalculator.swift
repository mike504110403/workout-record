import Foundation

/// Calculator for One Rep Max (1RM) using various formulas
struct OneRMCalculator {
    
    /// Calculate 1RM using specified formula
    /// - Parameters:
    ///   - weight: Weight lifted
    ///   - reps: Number of repetitions
    ///   - formula: Formula to use
    /// - Returns: Estimated 1RM
    static func calculate(weight: Double, reps: Int, using formula: User.OneRMFormula = .epley) -> Double {
        guard reps > 0 else { return weight }
        
        // If reps is 1, the weight is already 1RM
        if reps == 1 {
            return weight
        }
        
        return formula.calculate(weight: weight, reps: reps)
    }
    
    /// Calculate percentage of 1RM
    /// - Parameters:
    ///   - weight: Weight to calculate percentage for
    ///   - oneRM: One rep max
    /// - Returns: Percentage (0-100)
    static func calculatePercentage(weight: Double, of oneRM: Double) -> Double {
        guard oneRM > 0 else { return 0 }
        return (weight / oneRM) * 100
    }
    
    /// Calculate weight for a specific percentage of 1RM
    /// - Parameters:
    ///   - percentage: Percentage (0-100)
    ///   - oneRM: One rep max
    /// - Returns: Weight
    static func calculateWeight(forPercentage percentage: Double, of oneRM: Double) -> Double {
        return oneRM * (percentage / 100)
    }
    
    /// Get common training percentages
    /// - Parameter oneRM: One rep max
    /// - Returns: Dictionary of percentage to weight
    static func getTrainingPercentages(oneRM: Double) -> [Int: Double] {
        let percentages = [50, 60, 65, 70, 75, 80, 85, 90, 95]
        return Dictionary(uniqueKeysWithValues: percentages.map { percentage in
            (percentage, calculateWeight(forPercentage: Double(percentage), of: oneRM))
        })
    }
}

// MARK: - Reps to Percentage Guide
extension OneRMCalculator {
    /// Approximate percentage based on reps (general guideline)
    /// - Parameter reps: Number of reps
    /// - Returns: Approximate percentage of 1RM
    static func approximatePercentage(forReps reps: Int) -> Double {
        switch reps {
        case 1: return 100
        case 2: return 95
        case 3: return 93
        case 4: return 90
        case 5: return 87
        case 6: return 85
        case 7: return 83
        case 8: return 80
        case 9: return 77
        case 10: return 75
        case 11: return 73
        case 12: return 70
        default: return 70 - Double(reps - 12) * 2
        }
    }
    
    /// Suggested reps for percentage
    /// - Parameter percentage: Percentage of 1RM
    /// - Returns: Suggested rep range
    static func suggestedReps(forPercentage percentage: Double) -> ClosedRange<Int> {
        switch percentage {
        case 95...100: return 1...2
        case 90..<95: return 2...4
        case 85..<90: return 4...6
        case 80..<85: return 6...8
        case 75..<80: return 8...10
        case 70..<75: return 10...12
        default: return 12...15
        }
    }
}

