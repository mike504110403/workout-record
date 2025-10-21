import Foundation
import Combine

@MainActor
class VolumeChartViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var dataPoints: [VolumeDataPoint] = []
    @Published var selectedTimeRange: ChartTimeRange = .month
    @Published var selectedMuscleGroups: Set<MuscleGroupFilter> = [.all]
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Computed Properties
    var maxVolume: Double {
        guard !dataPoints.isEmpty else { return 100 }
        
        if selectedMuscleGroups.contains(.all) {
            return dataPoints.map { $0.totalVolume }.max() ?? 100
        } else {
            var maxValue: Double = 0
            for point in dataPoints {
                for filter in selectedMuscleGroups {
                    if let muscleGroup = filter.primaryMuscleGroup,
                       let volume = point.muscleGroupVolumes[muscleGroup] {
                        maxValue = max(maxValue, volume)
                    }
                }
            }
            return maxValue > 0 ? maxValue : 100
        }
    }
    
    var averageVolume: Double {
        guard !dataPoints.isEmpty else { return 0 }
        
        if selectedMuscleGroups.contains(.all) {
            let total = dataPoints.reduce(0) { $0 + $1.totalVolume }
            return total / Double(dataPoints.count)
        } else {
            var total: Double = 0
            var count = 0
            for point in dataPoints {
                for filter in selectedMuscleGroups {
                    if let muscleGroup = filter.primaryMuscleGroup,
                       let volume = point.muscleGroupVolumes[muscleGroup] {
                        total += volume
                        count += 1
                    }
                }
            }
            return count > 0 ? total / Double(count) : 0
        }
    }
    
    // MARK: - Private Properties
    private let workoutRepository = WorkoutRepository()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        loadData()
    }
    
    // MARK: - Public Methods
    
    func loadData() {
        isLoading = true
        errorMessage = nil
        
        do {
            // 計算日期範圍
            let endDate = Date()
            let calendar = Calendar.current
            guard let startDate = calendar.date(byAdding: .day, value: -selectedTimeRange.days, to: endDate) else {
                return
            }
            
            // 獲取訓練記錄
            let workouts = try workoutRepository.fetchByDateRange(from: startDate, to: endDate)
            
            // 按日期分組並計算容量
            dataPoints = aggregateVolumeByDate(workouts: workouts, in: selectedTimeRange)
            
            print("✅ 載入容量數據: \(dataPoints.count) 個數據點")
        } catch {
            errorMessage = "載入失敗: \(error.localizedDescription)"
            print("❌ 載入容量數據失敗: \(error)")
            dataPoints = []
        }
        
        isLoading = false
    }
    
    func changeTimeRange(_ range: ChartTimeRange) {
        selectedTimeRange = range
        loadData()
    }
    
    func toggleMuscleGroup(_ filter: MuscleGroupFilter) {
        if filter == .all {
            // 如果選擇"總容量"，清除其他選項
            selectedMuscleGroups = [.all]
        } else {
            // 移除"總容量"選項
            selectedMuscleGroups.remove(.all)
            
            // 切換選中狀態
            if selectedMuscleGroups.contains(filter) {
                selectedMuscleGroups.remove(filter)
                // 如果沒有選中任何肌群，默認選中"總容量"
                if selectedMuscleGroups.isEmpty {
                    selectedMuscleGroups.insert(.all)
                }
            } else {
                selectedMuscleGroups.insert(filter)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func aggregateVolumeByDate(workouts: [Workout], in timeRange: ChartTimeRange) -> [VolumeDataPoint] {
        let calendar = Calendar.current
        var volumeByDate: [Date: (total: Double, byMuscleGroup: [Exercise.PrimaryMuscleGroup: Double])] = [:]
        
        // 聚合數據
        for workout in workouts {
            let dateKey = calendar.startOfDay(for: workout.startedAt)
            
            if volumeByDate[dateKey] == nil {
                volumeByDate[dateKey] = (0, [:])
            }
            
            // 加總總容量
            volumeByDate[dateKey]!.total += workout.totalVolume
            
            // 按肌群加總（需要從 exercise 獲取肌群信息）
            for workoutExercise in workout.exercises {
                if let exercise = workoutExercise.exercise,
                   let muscleGroup = exercise.primaryMuscleGroup {
                    let currentVolume = volumeByDate[dateKey]!.byMuscleGroup[muscleGroup] ?? 0
                    volumeByDate[dateKey]!.byMuscleGroup[muscleGroup] = currentVolume + workoutExercise.totalVolume
                    print("✅ 肌群數據: \(muscleGroup.displayName) +\(workoutExercise.totalVolume)kg")
                } else {
                    print("⚠️ 訓練動作缺少 exercise 或 primaryMuscleGroup")
                    print("   - exerciseId: \(workoutExercise.exerciseId)")
                    print("   - exercise 是否為 nil: \(workoutExercise.exercise == nil)")
                    if let ex = workoutExercise.exercise {
                        print("   - exercise name: \(ex.name)")
                        print("   - primaryMuscleGroup 是否為 nil: \(ex.primaryMuscleGroup == nil)")
                    }
                }
            }
        }
        
        // 轉換為數據點並排序
        let points = volumeByDate.map { date, volumes in
            VolumeDataPoint(
                date: date,
                totalVolume: volumes.total,
                muscleGroupVolumes: volumes.byMuscleGroup
            )
        }.sorted { $0.date < $1.date }
        
        return points
    }
}

