import Foundation
import SwiftUI
import Combine

/// 體重記錄 ViewModel（API 版本）
/// 這是整合真實 API 的範例，展示如何替換 Mock 資料
class BodyWeightViewModelAPI: ObservableObject {
    @Published var bodyWeights: [BodyWeight] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    // MARK: - 獲取資料
    
    func fetchBodyWeights() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let records = try await BodyWeightService.shared.getBodyWeights()
            
            await MainActor.run {
                self.bodyWeights = records.sorted { $0.measuredAt > $1.measuredAt }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.showError = true
                self.isLoading = false
            }
        }
    }
    
    // MARK: - 新增記錄
    
    func addBodyWeight(
        weight: Double,
        bodyFat: Double? = nil,
        muscleMass: Double? = nil,
        notes: String? = nil,
        date: Date = Date()
    ) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let newRecord = try await BodyWeightService.shared.createBodyWeight(
                weight: weight,
                bodyFat: bodyFat,
                muscleMass: muscleMass,
                notes: notes,
                date: date
            )
            
            await MainActor.run {
                self.bodyWeights.insert(newRecord, at: 0)
                self.bodyWeights.sort { $0.measuredAt > $1.measuredAt }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.showError = true
                self.isLoading = false
            }
        }
    }
    
    // MARK: - 刪除記錄
    
    func deleteBodyWeight(id: UUID) async {
        do {
            try await BodyWeightService.shared.deleteBodyWeight(id: id.uuidString)
            
            await MainActor.run {
                self.bodyWeights.removeAll { $0.id == id }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.showError = true
            }
        }
    }
    
    // MARK: - 計算屬性（用於圖表）
    
    var chartData: [(Date, Double)] {
        bodyWeights
            .sorted { $0.measuredAt < $1.measuredAt }
            .suffix(30) // 最近 30 筆
            .map { ($0.measuredAt, $0.weight) }
    }
}

// MARK: - View 使用範例

struct BodyWeightViewAPI: View {
    @StateObject private var viewModel = BodyWeightViewModelAPI()
    @State private var showAddSheet = false
    
    var body: some View {
        NavigationView {
            ZStack {
                if viewModel.isLoading {
                    SwiftUI.ProgressView()
                        .overlay(
                            Text("載入中...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        )
                } else {
                    List {
                        Section {
                            // 圖表
                            if !viewModel.bodyWeights.isEmpty {
                                VStack {
                                    Text("體重趨勢")
                                        .font(.headline)
                                    // BodyWeightChartView(data: viewModel.chartData)
                                }
                            }
                        }
                        
                        Section("記錄") {
                            ForEach(viewModel.bodyWeights) { record in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("\(record.weight, specifier: "%.1f") kg")
                                            .font(.headline)
                                        Text(record.measuredAt, style: .date)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        Task {
                                            await viewModel.deleteBodyWeight(id: record.id)
                                        }
                                    } label: {
                                        Label("刪除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("體重記錄")
            .toolbar {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .task {
                await viewModel.fetchBodyWeights()
            }
            .refreshable {
                await viewModel.fetchBodyWeights()
            }
            .alert("錯誤", isPresented: $viewModel.showError) {
                Button("確定", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "未知錯誤")
            }
        }
    }
}

