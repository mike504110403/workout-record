import Foundation
import Combine

@MainActor
class PRViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var prSummaries: [PRSummary] = []
    @Published var filteredSummaries: [PRSummary] = []
    @Published var selectedMuscleGroup: Exercise.PrimaryMuscleGroup?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Computed Properties
    var muscleGroups: [Exercise.PrimaryMuscleGroup] {
        let groups = Set(prSummaries.compactMap { $0.primaryMuscleGroup })
        return Array(groups).sorted { $0.rawValue < $1.rawValue }
    }
    
    // MARK: - Private Properties
    private let repository = PersonalRecordRepository()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        loadPRs()
    }
    
    // MARK: - Public Methods
    
    func loadPRs() {
        isLoading = true
        errorMessage = nil
        
        do {
            let userId = DataMigrationService.getCurrentUserId()
            prSummaries = try repository.getPRSummary(userId: userId)
            applyFilter()
            
            print("✅ 載入 \(prSummaries.count) 個動作的 PR")
        } catch {
            errorMessage = "載入失敗: \(error.localizedDescription)"
            print("❌ 載入 PR 失敗: \(error)")
            prSummaries = []
            filteredSummaries = []
        }
        
        isLoading = false
    }
    
    func selectMuscleGroup(_ group: Exercise.PrimaryMuscleGroup?) {
        selectedMuscleGroup = group
        applyFilter()
    }
    
    func refresh() {
        loadPRs()
    }
    
    // MARK: - Private Methods
    
    private func applyFilter() {
        if let selectedGroup = selectedMuscleGroup {
            filteredSummaries = prSummaries.filter { $0.primaryMuscleGroup == selectedGroup }
        } else {
            filteredSummaries = prSummaries
        }
    }
}

