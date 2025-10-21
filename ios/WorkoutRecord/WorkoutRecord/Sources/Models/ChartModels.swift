import Foundation

// MARK: - Time Range

enum ChartTimeRange: String, CaseIterable {
    case week = "週"
    case month = "月"
    case threeMonths = "3月"
    case year = "年"
    
    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .threeMonths: return 90
        case .year: return 365
        }
    }
    
    var dateFormat: String {
        switch self {
        case .week: return "MM/dd"
        case .month: return "MM/dd"
        case .threeMonths: return "MM/dd"
        case .year: return "yyyy/MM"
        }
    }
}

// MARK: - Volume Data Point

struct VolumeDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let totalVolume: Double
    let muscleGroupVolumes: [Exercise.PrimaryMuscleGroup: Double]
    
    init(date: Date, totalVolume: Double, muscleGroupVolumes: [Exercise.PrimaryMuscleGroup: Double] = [:]) {
        self.date = date
        self.totalVolume = totalVolume
        self.muscleGroupVolumes = muscleGroupVolumes
    }
}

// MARK: - Muscle Group Filter

enum MuscleGroupFilter: String, CaseIterable, Identifiable {
    case all = "總容量"
    case chest = "胸部"
    case back = "背部"
    case legs = "腿部"
    case shoulders = "肩部"
    case arms = "手臂"
    case core = "核心"
    
    var id: String { rawValue }
    
    var primaryMuscleGroup: Exercise.PrimaryMuscleGroup? {
        switch self {
        case .all: return nil
        case .chest: return .chest
        case .back: return .back
        case .legs: return .legs
        case .shoulders: return .shoulders
        case .arms: return .arms
        case .core: return .core
        }
    }
    
    var color: String {
        switch self {
        case .all: return "blue"
        case .chest: return "red"
        case .back: return "blue"
        case .legs: return "green"
        case .shoulders: return "orange"
        case .arms: return "purple"
        case .core: return "yellow"
        }
    }
}

