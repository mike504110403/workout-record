import SwiftUI

struct BodyWeightView: View {
    @StateObject private var viewModel = BodyWeightViewModel()
    @State private var showAddSheet = false
    
    var body: some View {
        NavigationStack {
            VStack {
                if viewModel.bodyWeights.isEmpty {
                    EmptyBodyWeightView {
                        showAddSheet = true
                    }
                } else {
                    bodyWeightContent
                }
            }
            .navigationTitle("體重記錄")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddBodyWeightSheet(viewModel: viewModel)
            }
        }
    }
    
    private var bodyWeightContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Current weight card
                currentWeightCard
                
                // Chart
                if !viewModel.bodyWeights.isEmpty {
                    BodyWeightChartView(
                        data: viewModel.chartData,
                        targetWeight: nil,  // TODO: Get from user settings
                        timeRange: .month
                    )
                }
                
                // Simple trend indicator
                trendCard
                
                // Weight list
                weightList
            }
            .padding()
        }
    }
    
    private var currentWeightCard: some View {
        VStack(spacing: 12) {
            Text("當前體重")
                .font(.headline)
                .foregroundColor(.secondary)
            
            if let latest = viewModel.bodyWeights.first {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", latest.weight))
                        .font(.system(size: 48, weight: .bold))
                    Text("kg")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                
                Text(latest.measuredAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    private var trendCard: some View {
        HStack(spacing: 20) {
            BodyWeightStatItem(
                title: "變化",
                value: viewModel.weightChange,
                unit: "kg",
                trend: viewModel.weightChange < 0 ? .down : .up
            )
            
            Divider()
            
            BodyWeightStatItem(
                title: "平均",
                value: viewModel.averageWeight,
                unit: "kg"
            )
            
            Divider()
            
            BodyWeightStatItem(
                title: "記錄",
                value: Double(viewModel.bodyWeights.count),
                unit: "筆"
            )
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    private var weightList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("歷史記錄")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 8) {
                ForEach(viewModel.bodyWeights) { weight in
                    BodyWeightRow(
                        weight: weight,
                        onDelete: { viewModel.deleteWeight(weight) }
                    )
                }
            }
        }
    }
}

// MARK: - Add Body Weight Sheet
struct AddBodyWeightSheet: View {
    @ObservedObject var viewModel: BodyWeightViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var weight: String = ""
    @State private var selectedDate = Date()
    @State private var note: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("體重") {
                    HStack {
                        TextField("請輸入體重", text: $weight)
                            .keyboardType(.decimalPad)
                            .font(.title2)
                        
                        Text("kg")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("測量時間") {
                    DatePicker(
                        "日期時間",
                        selection: $selectedDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
                
                Section("備註（選填）") {
                    TextField("例如：早上空腹", text: $note)
                }
            }
            .navigationTitle("記錄體重")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("儲存") {
                        saveWeight()
                    }
                    .disabled(weight.isEmpty)
                }
            }
        }
    }
    
    private func saveWeight() {
        guard let weightValue = Double(weight) else { return }
        
        viewModel.addWeight(
            weight: weightValue,
            measuredAt: selectedDate,
            note: note.isEmpty ? nil : note
        )
        
        dismiss()
    }
}

// MARK: - Empty State
struct EmptyBodyWeightView: View {
    let onAdd: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "scalemass")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("尚未記錄體重")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("開始記錄你的體重變化")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button {
                onAdd()
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("記錄第一筆體重")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(12)
            }
        }
        .padding()
    }
}

// MARK: - Body Weight Row
struct BodyWeightRow: View {
    let weight: BodyWeight
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", weight.weight))
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("kg")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text(weight.measuredAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let note = weight.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }
}

// MARK: - Stat Item (Body Weight specific)
private struct BodyWeightStatItem: View {
    let title: String
    let value: Double
    let unit: String
    var trend: Trend? = nil
    
    enum Trend {
        case up, down
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let trend = trend {
                    Image(systemName: trend == .up ? "arrow.up" : "arrow.down")
                        .font(.caption)
                        .foregroundColor(trend == .down ? .green : .red)
                }
                
                Text(String(format: "%.1f", abs(value)))
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    BodyWeightView()
}

