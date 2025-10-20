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
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        loadMockData()
    }
    
    // MARK: - Public Methods
    func addWeight(weight: Double, measuredAt: Date, note: String?) {
        let newWeight = BodyWeight(
            userId: UUID(), // TODO: Use actual user ID
            weight: weight,
            measuredAt: measuredAt,
            note: note
        )
        
        bodyWeights.insert(newWeight, at: 0)
        bodyWeights.sort { $0.measuredAt > $1.measuredAt }
        
        // TODO: Save to repository
    }
    
    func updateWeight(_ weight: BodyWeight, newWeight: Double, note: String?) {
        guard let index = bodyWeights.firstIndex(where: { $0.id == weight.id }) else { return }
        
        var updated = weight
        updated.weight = newWeight
        updated.note = note
        updated.updatedAt = Date()
        
        bodyWeights[index] = updated
        
        // TODO: Update in repository
    }
    
    func deleteWeight(_ weight: BodyWeight) {
        bodyWeights.removeAll { $0.id == weight.id }
        
        // TODO: Delete from repository
    }
    
    func refresh() {
        isLoading = true
        // TODO: Fetch from repository
        isLoading = false
    }
    
    // MARK: - Private Methods
    private func loadMockData() {
        // Generate mock body weight data for the past 30 days
        let calendar = Calendar.current
        let today = Date()
        
        bodyWeights = (0..<30).compactMap { daysAgo in
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else {
                return nil
            }
            
            // Simulate weight fluctuation around 75kg
            let baseWeight = 75.0
            let variation = Double.random(in: -1.5...1.5)
            let trend = -0.05 * Double(daysAgo) // Slight downward trend
            let weight = baseWeight + variation + trend
            
            let notes = [
                "早上空腹",
                "晚上測量",
                "運動後",
                "飯後",
                nil,
                nil,
                nil
            ]
            
            return BodyWeight(
                userId: UUID(),
                weight: weight,
                measuredAt: date,
                note: notes.randomElement() ?? nil
            )
        }
        
        bodyWeights.sort { $0.measuredAt > $1.measuredAt }
    }
}

