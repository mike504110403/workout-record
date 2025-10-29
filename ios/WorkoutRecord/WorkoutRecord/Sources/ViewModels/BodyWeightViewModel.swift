import Foundation
import Combine

@MainActor
class BodyWeightViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var bodyWeights: [BodyWeight] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Computed Properties
    var averageWeight: Double {
        guard !bodyWeights.isEmpty else { return 0 }
        let sum = bodyWeights.reduce(0.0) { $0 + $1.weight }
        return sum / Double(bodyWeights.count)
    }
    
    var weightChange: Double {
        guard bodyWeights.count >= 2 else { return 0 }
        let latest = bodyWeights[0].weight
        let previous = bodyWeights[1].weight
        return latest - previous
    }
    
    var maxWeight: Double {
        bodyWeights.map { $0.weight }.max() ?? 0
    }
    
    var minWeight: Double {
        bodyWeights.map { $0.weight }.min() ?? 0
    }
    
    var chartData: [BodyWeightTrendPoint] {
        bodyWeights.map { weight in
            BodyWeightTrendPoint(
                date: weight.measuredAt,
                weight: weight.weight
            )
        }
    }
    
    // MARK: - Private Properties
    private let repository = BodyWeightRepository()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        loadData()
    }
    
    // MARK: - Public Methods
    func addWeight(weight: Double, measuredAt: Date, note: String?) {
        let userId = DataMigrationService.getCurrentUserId()
        let newWeight = BodyWeight(
            userId: userId,
            weight: weight,
            measuredAt: measuredAt,
            note: note
        )
        
        do {
            _ = try repository.create(bodyWeight: newWeight)
            loadData() // 重新加載數據
        } catch {
            errorMessage = "保存失敗: \(error.localizedDescription)"
            print("❌ 保存體重失敗: \(error)")
        }
    }
    
    func updateWeight(_ weight: BodyWeight, newWeight: Double, note: String?) {
        var updated = weight
        updated.weight = newWeight
        updated.note = note
        updated.updatedAt = Date()
        
        do {
            try repository.update(bodyWeight: updated)
            loadData()
        } catch {
            errorMessage = "更新失敗: \(error.localizedDescription)"
            print("❌ 更新體重失敗: \(error)")
        }
    }
    
    func deleteWeight(_ weight: BodyWeight) {
        do {
            try repository.delete(id: weight.id)
            loadData()
        } catch {
            errorMessage = "刪除失敗: \(error.localizedDescription)"
            print("❌ 刪除體重失敗: \(error)")
        }
    }
    
    func refresh() {
        loadData()
    }
    
    func loadData() {
        isLoading = true
        errorMessage = nil
        
        do {
            bodyWeights = try repository.fetchAll()
            print("✅ 載入 \(bodyWeights.count) 筆體重記錄")
        } catch {
            errorMessage = "載入失敗: \(error.localizedDescription)"
            print("❌ 載入體重數據失敗: \(error)")
            bodyWeights = []
        }
        
        isLoading = false
    }
    
    // MARK: - Statistics
    
    func getLatestWeight() -> BodyWeight? {
        do {
            return try repository.getLatestWeight()
        } catch {
            print("❌ 獲取最新體重失敗: \(error)")
            return nil
        }
    }
    
    func getAverageWeight(days: Int) -> Double? {
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else {
            return nil
        }
        
        do {
            return try repository.getAverageWeight(from: startDate, to: endDate)
        } catch {
            print("❌ 計算平均體重失敗: \(error)")
            return nil
        }
    }
}

