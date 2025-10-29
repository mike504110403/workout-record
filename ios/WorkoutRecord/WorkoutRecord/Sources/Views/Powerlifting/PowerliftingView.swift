import SwiftUI
import Charts

/// 經典三項力量訓練視圖
struct PowerliftingView: View {
    @StateObject private var viewModel = PowerliftingViewModel()
    @State private var showAddPR = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 三項總和卡片
                totalCard
                
                // 動作選擇器
                liftPicker
                
                // 1RM 趨勢圖
                oneRMChart
                
                // 當前 PR 卡片
                if let pr = viewModel.currentPR {
                    currentPRCard(pr: pr)
                }
                
                // 歷史記錄
                recordsList
            }
            .padding()
        }
        .navigationTitle("經典三項")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddPR = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddPR) {
            AddPRSheet(viewModel: viewModel)
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
                Text(String(format: "%.1f", viewModel.totalLifts))
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.blue)
                
                Text("kg")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            
            // 各項 PR
            HStack(spacing: 20) {
                ForEach(PowerLift.allCases) { lift in
                    if let pr = viewModel.records.filter({ $0.lift == lift }).max(by: { $0.oneRepMax < $1.oneRepMax }) {
                        VStack(spacing: 4) {
                            Text(lift.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(String(format: "%.1f", pr.oneRepMax))
                                .font(.headline)
                                .fontWeight(.bold)
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
    
    // MARK: - 1RM Chart
    
    private var oneRMChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1RM 趨勢")
                .font(.headline)
            
            if viewModel.chartData.isEmpty {
                emptyChartView
            } else {
                Chart(viewModel.chartData) { point in
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("1RM", point.oneRepMax)
                    )
                    .foregroundStyle(.blue)
                    .symbol(Circle())
                    
                    PointMark(
                        x: .value("日期", point.date),
                        y: .value("1RM", point.oneRepMax)
                    )
                    .foregroundStyle(point.isManualEntry ? .orange : .blue)
                    .symbolSize(60)
                }
                .frame(height: 250)
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
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    private var emptyChartView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            
            Text("尚無 1RM 記錄")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("完成訓練或手動新增 PR")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(height: 250)
    }
    
    // MARK: - Current PR Card
    
    private func currentPRCard(pr: PowerLiftRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundColor(.orange)
                
                Text("當前 PR")
                    .font(.headline)
                
                Spacer()
                
                if pr.isManualEntry {
                    Text("手動輸入")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("1RM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(String(format: "%.1f kg", pr.oneRepMax))
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("重量 × 次數")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(String(format: "%.1f", pr.weight)) kg × \(pr.reps)")
                        .font(.headline)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("達成日期")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(pr.achievedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.1), Color.yellow.opacity(0.1)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(12)
    }
    
    // MARK: - Records List
    
    private var recordsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("歷史記錄")
                .font(.headline)
            
            if viewModel.currentRecords.isEmpty {
                Text("尚無記錄")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(viewModel.currentRecords.prefix(10)) { record in
                    RecordRow(record: record)
                }
            }
        }
    }
}

// MARK: - Record Row

struct RecordRow: View {
    let record: PowerLiftRecord
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.achievedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(String(format: "%.1f", record.weight)) kg × \(record.reps) 次")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("1RM")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(String(format: "%.1f kg", record.oneRepMax))
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            if record.isManualEntry {
                Image(systemName: "pencil.circle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Add PR Sheet

struct AddPRSheet: View {
    @ObservedObject var viewModel: PowerliftingViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var weight: String = ""
    @State private var reps: Int = 1
    @State private var date = Date()
    
    var body: some View {
        NavigationStack {
            Form {
                Section("動作") {
                    Picker("選擇動作", selection: $viewModel.selectedLift) {
                        ForEach(PowerLift.allCases) { lift in
                            Text(lift.rawValue).tag(lift)
                        }
                    }
                }
                
                Section("重量與次數") {
                    HStack {
                        TextField("重量", text: $weight)
                            .keyboardType(.decimalPad)
                        
                        Text("kg")
                            .foregroundColor(.secondary)
                    }
                    
                    Stepper("次數: \(reps)", value: $reps, in: 1...20)
                    
                    if let w = Double(weight) {
                        let oneRM = w * (1 + Double(reps) / 30)
                        HStack {
                            Text("預估 1RM")
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text(String(format: "%.1f kg", oneRM))
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Section("日期") {
                    DatePicker(
                        "達成日期",
                        selection: $date,
                        displayedComponents: .date
                    )
                }
            }
            .navigationTitle("新增 PR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("儲存") {
                        savePR()
                    }
                    .disabled(weight.isEmpty)
                }
            }
        }
    }
    
    private func savePR() {
        guard let weightValue = Double(weight) else { return }
        
        viewModel.addManualPR(weight: weightValue, reps: reps, date: date)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        PowerliftingView()
    }
}

