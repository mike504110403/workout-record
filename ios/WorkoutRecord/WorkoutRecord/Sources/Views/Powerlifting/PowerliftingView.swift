import SwiftUI
import Charts

/// 經典三項力量訓練視圖
struct PowerliftingView: View {
    @StateObject private var viewModel = PowerliftingViewModel()
    @StateObject private var globalSettings = GlobalSettingsManager.shared
    @State private var showAddRecord = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 三項總和卡片
                totalCard
                
                // 動作選擇器
                liftPicker
                
                // 手動記錄（三項表）
                manualRecordsSection
            }
            .padding()
        }
        .navigationTitle("經典三項")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddRecord = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddRecord) {
            AddPowerLiftRecordSheet(
                lift: viewModel.selectedLift,
                onSave: { record in
                    viewModel.addManualRecord(
                        weight: record.weight,
                        reps: record.reps,
                        date: record.achievedAt,
                        note: record.note
                    )
                }
            )
        }
        .onAppear {
            viewModel.refresh()
        }
    }
    
    // MARK: - Total Card
    
    private var totalCard: some View {
        VStack(spacing: 12) {
            Text("三項總和")
                .font(.headline)
                .foregroundColor(.secondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(WeightFormatter.shared.formatValue(viewModel.totalLifts))
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.blue)
                
                Text(globalSettings.weightUnit.symbol)
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            
            // 各項 PR
            HStack(spacing: 20) {
                ForEach(PowerLift.allCases) { lift in
                    if let pr = viewModel.manualRecords.filter({ $0.lift == lift }).max(by: { $0.oneRepMax < $1.oneRepMax }) {
                        VStack(spacing: 4) {
                            Text(lift.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(WeightFormatter.shared.formatValue(pr.oneRepMax))
                                .font(.headline)
                                .fontWeight(.bold)
                        }
                    } else {
                        VStack(spacing: 4) {
                            Text(lift.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("--")
                                .font(.headline)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
    }
    
    // MARK: - Lift Picker
    
    private var liftPicker: some View {
        Picker("動作", selection: $viewModel.selectedLift) {
            ForEach(PowerLift.allCases) { lift in
                Text(lift.rawValue).tag(lift)
            }
        }
        .pickerStyle(.segmented)
    }
    
    // MARK: - Manual Records Section (三項表)
    
    private var manualRecordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("三項表記錄")
                    .font(.headline)
                
                Spacer()
                
                if let pr = viewModel.currentManualPR {
                    Text("PR: \(String(format: "%.1f", pr.oneRepMax)) kg")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            // 1RM 趨勢圖（僅顯示手動記錄）
            if viewModel.chartData.isEmpty {
                emptyChartView(message: "尚無三項表記錄\n點擊右上角 + 開始記錄")
            } else {
                Chart(viewModel.chartData) { point in
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("1RM", point.oneRepMax)
                    )
                    .foregroundStyle(.blue)
                    
                    PointMark(
                        x: .value("日期", point.date),
                        y: .value("1RM", point.oneRepMax)
                    )
                    .foregroundStyle(.blue)
                    .symbolSize(80)
                }
                .frame(height: 200)
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date, format: .dateTime.month(.abbreviated).day())
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
            }
            
            // 歷史記錄列表
            if !viewModel.currentManualRecords.isEmpty {
                ForEach(viewModel.currentManualRecords.prefix(5)) { record in
                    ManualRecordRow(
                        record: record,
                        onDelete: {
                            viewModel.deleteManualRecord(record)
                        }
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - System Estimated Section (系統推估)
    
    private var systemEstimatedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("訓練推估")
                    .font(.headline)
                
                Spacer()
                
                if let pr = viewModel.currentSystemPR {
                    Text("推估: \(WeightFormatter.shared.formatValue(pr.oneRepMax)) \(globalSettings.weightUnit.symbol)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            Text("根據您的訓練記錄推算")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if viewModel.currentSystemRecords.isEmpty {
                emptyChartView(message: "尚無訓練數據\n開始訓練後系統會自動計算")
            } else {
                // 系統推估記錄列表（最多顯示3筆最佳記錄）
                ForEach(viewModel.currentSystemRecords.prefix(3)) { record in
                    SystemRecordRow(record: record)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Empty Chart View
    
    private func emptyChartView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(height: 200)
    }
}

// MARK: - Manual Record Row

struct ManualRecordRow: View {
    let record: PowerLiftRecord
    let onDelete: () -> Void
    
    @StateObject private var globalSettings = GlobalSettingsManager.shared
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.achievedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(WeightFormatter.shared.format(record.weight, unit: globalSettings.weightUnit)) × \(record.reps) 次")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let note = record.note, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("1RM")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(WeightFormatter.shared.format(record.oneRepMax, unit: globalSettings.weightUnit))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("刪除", systemImage: "trash")
            }
        }
    }
}

// MARK: - System Record Row

struct SystemRecordRow: View {
    let record: PowerLiftRecord
    
    @StateObject private var globalSettings = GlobalSettingsManager.shared
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.achievedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(WeightFormatter.shared.format(record.weight, unit: globalSettings.weightUnit)) × \(record.reps) 次")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption2)
                    Text("推估")
                }
                .font(.caption)
                .foregroundColor(.orange)
                
                Text(WeightFormatter.shared.format(record.oneRepMax, unit: globalSettings.weightUnit))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    NavigationStack {
        PowerliftingView()
    }
}
