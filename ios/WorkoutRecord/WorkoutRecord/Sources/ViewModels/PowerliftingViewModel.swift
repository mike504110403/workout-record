import Foundation
import Combine
import CoreData

/// 經典三項力量訓練 ViewModel
class PowerliftingViewModel: ObservableObject {
    @Published var selectedLift: PowerLift = .squat
    @Published var records: [PowerLiftRecord] = []
    @Published var isLoading = false
    @Published var showAddPRSheet = false
    
    private let workoutRepository = WorkoutRepository()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        refresh()
    }
    
    // MARK: - Public Methods
    
    func refresh() {
        Task {
            await loadRecords()
        }
    }
    
    func selectLift(_ lift: PowerLift) {
        selectedLift = lift
    }
    
    /// 手動新增 PR 記錄
    func addManualPR(weight: Double, reps: Int = 1, date: Date) {
        let oneRM = calculateOneRM(weight: weight, reps: reps)
        
        let record = PowerLiftRecord(
            lift: selectedLift,
            weight: weight,
            reps: reps,
            oneRepMax: oneRM,
            achievedAt: date,
            isManualEntry: true
        )
        
        // TODO: 保存到 CoreData
        records.append(record)
        records.sort { $0.achievedAt > $1.achievedAt }
    }
    
    // MARK: - Computed Properties
    
    var currentRecords: [PowerLiftRecord] {
        records.filter { $0.lift == selectedLift }
            .sorted { $0.achievedAt > $1.achievedAt }
    }
    
    var currentPR: PowerLiftRecord? {
        currentRecords.max { $0.oneRepMax < $1.oneRepMax }
    }
    
    var chartData: [OneRMDataPoint] {
        currentRecords.map { record in
            OneRMDataPoint(
                date: record.achievedAt,
                oneRM: record.oneRepMax,
                isManualEntry: record.isManualEntry
            )
        }
        .sorted { $0.date < $1.date }
    }
    
    var totalLifts: Double {
        var total = 0.0
        for lift in PowerLift.allCases {
            if let pr = records.filter({ $0.lift == lift }).max(by: { $0.oneRepMax < $1.oneRepMax }) {
                total += pr.oneRepMax
            }
        }
        return total
    }
    
    // MARK: - Private Methods
    
    private func loadRecords() async {
        await MainActor.run {
            isLoading = true
        }
        
        do {
            // 從訓練記錄中提取三項數據
            let workouts = try workoutRepository.fetchAll()
            var extractedRecords: [PowerLiftRecord] = []
            
            for workout in workouts {
                let exercises = workout.exercises
                
                for exercise in exercises {
                    guard let exerciseName = exercise.exercise?.name else { continue }
                    
                    // 檢查是否為三項動作之一
                    for lift in PowerLift.allCases {
                        if lift.matches(exerciseName: exerciseName) {
                            // 找出該動作的最大重量組
                            for set in exercise.sets {
                                let oneRM = calculateOneRM(weight: set.weight, reps: set.reps)
                                
                                let record = PowerLiftRecord(
                                    lift: lift,
                                    weight: set.weight,
                                    reps: set.reps,
                                    oneRepMax: oneRM,
                                    achievedAt: workout.startedAt,
                                    isManualEntry: false
                                )
                                
                                extractedRecords.append(record)
                            }
                        }
                    }
                }
            }
            
            await MainActor.run {
                self.records = extractedRecords
                self.isLoading = false
            }
        } catch {
            print("❌ 載入力量記錄失敗: \(error)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    private func calculateOneRM(weight: Double, reps: Int) -> Double {
        if reps == 1 {
            return weight
        }
        
        // 使用 Epley 公式
        return weight * (1 + Double(reps) / 30)
    }
}

// MARK: - Data Models

struct OneRMDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let oneRM: Double
    let isManualEntry: Bool
}

