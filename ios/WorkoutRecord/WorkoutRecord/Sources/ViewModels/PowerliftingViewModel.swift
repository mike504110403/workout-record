import Foundation
import Combine
import CoreData

/// 經典三項力量訓練 ViewModel
@MainActor
class PowerliftingViewModel: ObservableObject {
    @Published var selectedLift: PowerLift = .squat
    @Published var manualRecords: [PowerLiftRecord] = [] // 手動輸入的記錄
    @Published var systemEstimatedRecords: [PowerLiftRecord] = [] // 系統從訓練推估的記錄
    @Published var isLoading = false
    @Published var showAddPRSheet = false
    
    private let powerLiftRepository = PowerLiftRepository()
    private let workoutRepository = WorkoutRepository()
    private let personalRecordRepository = PersonalRecordRepository()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        refresh()
    }
    
    // MARK: - Public Methods
    
    func refresh() {
        isLoading = true
        Task {
            await loadRecords()
            isLoading = false
        }
    }
    
    func selectLift(_ lift: PowerLift) {
        selectedLift = lift
    }
    
    /// 手動新增 PR 記錄
    func addManualRecord(weight: Double, reps: Int = 1, date: Date, note: String? = nil) {
        let userId = DataMigrationService.getCurrentUserId()
        let oneRM = OneRMCalculator.calculate(weight: weight, reps: reps)
        
        let record = PowerLiftRecord(
            userId: userId,
            lift: selectedLift,
            weight: weight,
            reps: reps,
            oneRepMax: oneRM,
            achievedAt: date,
            note: note
        )
        
        do {
            _ = try powerLiftRepository.create(record: record)
            manualRecords.append(record)
            manualRecords.sort { $0.achievedAt > $1.achievedAt }
            
            print("✅ 手動三項記錄已保存: \(selectedLift.rawValue) \(weight)kg × \(reps)")
        } catch {
            print("❌ 保存三項記錄失敗: \(error)")
        }
    }
    
    /// 刪除手動記錄
    func deleteManualRecord(_ record: PowerLiftRecord) {
        do {
            try powerLiftRepository.delete(id: record.id)
            manualRecords.removeAll { $0.id == record.id }
            print("✅ 已刪除三項記錄")
        } catch {
            print("❌ 刪除三項記錄失敗: \(error)")
        }
    }
    
    // MARK: - Computed Properties
    
    /// 當前選中動作的手動記錄
    var currentManualRecords: [PowerLiftRecord] {
        manualRecords.filter { $0.lift == selectedLift }
            .sorted { $0.achievedAt > $1.achievedAt }
    }
    
    /// 當前選中動作的系統推估記錄
    var currentSystemRecords: [PowerLiftRecord] {
        systemEstimatedRecords.filter { $0.lift == selectedLift }
            .sorted { $0.achievedAt > $1.achievedAt }
    }
    
    /// 當前選中動作的最佳手動記錄
    var currentManualPR: PowerLiftRecord? {
        currentManualRecords.max { $0.oneRepMax < $1.oneRepMax }
    }
    
    /// 當前選中動作的系統推估最佳記錄
    var currentSystemPR: PowerLiftRecord? {
        currentSystemRecords.max { $0.oneRepMax < $1.oneRepMax }
    }
    
    /// 圖表數據（僅顯示手動記錄）
    var chartData: [OneRMDataPoint] {
        currentManualRecords.map { record in
            OneRMDataPoint(
                date: record.achievedAt,
                oneRepMax: record.oneRepMax
            )
        }
        .sorted { $0.date < $1.date }
    }
    
    /// 三項總和（使用手動記錄的最佳成績）
    var totalLifts: Double {
        var total = 0.0
        for lift in PowerLift.allCases {
            if let pr = manualRecords.filter({ $0.lift == lift }).max(by: { $0.oneRepMax < $1.oneRepMax }) {
                total += pr.oneRepMax
            }
        }
        return total
    }
    
    // MARK: - Private Methods
    
    private func loadRecords() async {
        let userId = DataMigrationService.getCurrentUserId()
        
        do {
            // 1. 載入手動輸入的記錄
            let savedRecords = try powerLiftRepository.getAll(userId: userId)
            await MainActor.run {
                self.manualRecords = savedRecords
            }
            
            // 2. 從個人記錄（PersonalRecord）中提取系統推估的記錄
            let personalRecords = try personalRecordRepository.getAllPersonalRecords()
            var extractedRecords: [PowerLiftRecord] = []
            
            print("🔍 檢查 PersonalRecord: 總共 \(personalRecords.count) 筆")
            
            for pr in personalRecords {
                if let exercise = pr.exercise {
                    print("   - 動作: \(exercise.name), 重量: \(pr.weight)kg, 次數: \(pr.reps), 1RM: \(pr.oneRepMax)kg")
                    
                    // 檢查是否為三項動作之一
                    for lift in PowerLift.allCases {
                        if lift.matches(exerciseName: exercise.name) {
                            print("   ✅ 匹配到三項: \(lift.rawValue)")
                            let record = PowerLiftRecord(
                                userId: userId,
                                lift: lift,
                                weight: pr.weight,
                                reps: pr.reps,
                                oneRepMax: pr.oneRepMax,
                                achievedAt: pr.achievedAt,
                                note: nil
                            )
                            extractedRecords.append(record)
                            break // 找到匹配的動作後跳出
                        }
                    }
                } else {
                    print("   ⚠️ PR 缺少 exercise 關聯: exerciseId=\(pr.exerciseId)")
                }
            }
            
            await MainActor.run {
                self.systemEstimatedRecords = extractedRecords
            }
            
            print("✅ 載入三項記錄: 手動 \(savedRecords.count) 筆，系統推估 \(extractedRecords.count) 筆")
            
        } catch {
            print("❌ 載入力量記錄失敗: \(error)")
        }
    }
}

// MARK: - Data Models

struct OneRMDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let oneRepMax: Double
}
