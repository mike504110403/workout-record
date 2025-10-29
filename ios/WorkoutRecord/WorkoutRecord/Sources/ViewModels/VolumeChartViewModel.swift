import Foundation
import Combine
import UIKit

@MainActor
class VolumeChartViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var dataPoints: [VolumeDataPoint] = []
    @Published var selectedTimeRange: ChartTimeRange = .month
    @Published var selectedMuscleGroups: Set<MuscleGroupFilter> = [.all]
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Dependencies
    private let globalSettings = GlobalSettingsManager.shared
    
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
        setupNotificationObservers()
    }
    
    deinit {
        cancellables.removeAll()
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
    
    // MARK: - Private Methods
    
    private func setupNotificationObservers() {
        // 監聽訓練完成通知
        NotificationCenter.default.publisher(for: .workoutCompleted)
            .sink { [weak self] _ in
                print("📊 收到訓練完成通知，刷新容量圖表")
                self?.loadData()
            }
            .store(in: &cancellables)
        
        // 監聽應用變為活躍狀態（從後台返回時刷新）
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                print("📊 應用變為活躍狀態，刷新容量圖表")
                self?.loadData()
            }
            .store(in: &cancellables)
    }
    
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
            
            // 按肌群加總（優先使用 exercise 關聯，如果沒有則嘗試從 exerciseName 推斷）
            for workoutExercise in workout.exercises {
                var muscleGroup: Exercise.PrimaryMuscleGroup?
                
                // 優先使用 exercise 關聯的肌群信息
                if let exercise = workoutExercise.exercise,
                   let primaryMuscleGroup = exercise.primaryMuscleGroup {
                    muscleGroup = primaryMuscleGroup
                } else {
                    // 如果沒有 exercise 關聯，嘗試從 exerciseName 推斷肌群
                    muscleGroup = inferMuscleGroupFromName(workoutExercise.exerciseName ?? "")
                }
                
                if let muscleGroup = muscleGroup {
                    let currentVolume = volumeByDate[dateKey]!.byMuscleGroup[muscleGroup] ?? 0
                    volumeByDate[dateKey]!.byMuscleGroup[muscleGroup] = currentVolume + workoutExercise.totalVolume
                    print("✅ 肌群數據: \(muscleGroup.displayName) +\(workoutExercise.totalVolume)kg")
                } else {
                    print("⚠️ 無法確定肌群: exerciseId=\(workoutExercise.exerciseId), exerciseName=\(workoutExercise.exerciseName ?? "nil")")
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
    
    /// 從動作名稱推斷主要肌群
    private func inferMuscleGroupFromName(_ exerciseName: String) -> Exercise.PrimaryMuscleGroup? {
        let name = exerciseName.lowercased()
        
        // 胸部動作關鍵詞
        if name.contains("胸") || name.contains("chest") || name.contains("飛鳥") || name.contains("press") {
            return .chest
        }
        
        // 背部動作關鍵詞
        if name.contains("背") || name.contains("back") || name.contains("拉") || name.contains("pull") || name.contains("划船") {
            return .back
        }
        
        // 腿部動作關鍵詞
        if name.contains("腿") || name.contains("leg") || name.contains("蹲") || name.contains("squat") || name.contains("深蹲") {
            return .legs
        }
        
        // 肩部動作關鍵詞
        if name.contains("肩") || name.contains("shoulder") || name.contains("推舉") || name.contains("press") {
            return .shoulders
        }
        
        // 手臂動作關鍵詞
        if name.contains("手臂") || name.contains("arm") || name.contains("二頭") || name.contains("三頭") || name.contains("bicep") || name.contains("tricep") {
            return .arms
        }
        
        // 核心動作關鍵詞
        if name.contains("核心") || name.contains("core") || name.contains("腹") || name.contains("abs") || name.contains("平板") {
            return .core
        }
        
        return nil
    }
    
    // MARK: - Formatted Values
    var formattedAverageVolume: String {
        return globalSettings.formatWeight(averageVolume)
    }
    
    var formattedHighestVolume: String {
        return globalSettings.formatWeight(maxVolume)
    }
    
    var formattedMaxVolume: String {
        return globalSettings.formatWeight(maxVolume)
    }
}

