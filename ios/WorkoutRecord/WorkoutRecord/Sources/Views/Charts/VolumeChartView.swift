import SwiftUI
import Charts

struct VolumeChartView: View {
    @StateObject private var viewModel = VolumeChartViewModel()
    
    var body: some View {
        VStack(spacing: 16) {
            // 標題和統計
            headerSection
            
            // 時間範圍選擇
            timeRangePicker
            
            // 圖表
            chartSection
            
            // 肌群篩選
            muscleGroupFilters
            
            // 統計摘要
            statsSection
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("訓練容量趨勢")
                .font(.title2)
                .fontWeight(.bold)
            
            if viewModel.isLoading {
                SwiftUI.ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Time Range Picker
    private var timeRangePicker: some View {
        Picker("時間範圍", selection: $viewModel.selectedTimeRange) {
            ForEach(ChartTimeRange.allCases, id: \.self) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: viewModel.selectedTimeRange) { _, newValue in
            viewModel.changeTimeRange(newValue)
        }
    }
    
    // MARK: - Chart
    private var chartSection: some View {
        Group {
            if viewModel.dataPoints.isEmpty {
                emptyChartView
            } else {
                volumeChart
            }
        }
        .frame(height: 250)
    }
    
    private var emptyChartView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("尚無訓練數據")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("完成訓練後這裡會顯示容量趨勢")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var volumeChart: some View {
        Chart {
            // 總容量線
            if viewModel.selectedMuscleGroups.contains(.all) {
                ForEach(viewModel.dataPoints) { point in
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("容量", point.totalVolume)
                    )
                    .foregroundStyle(.blue)
                    .symbol(Circle())
                    
                    AreaMark(
                        x: .value("日期", point.date),
                        y: .value("容量", point.totalVolume)
                    )
                    .foregroundStyle(.blue.opacity(0.1))
                }
            }
            
            // 各肌群線
            ForEach(Array(viewModel.selectedMuscleGroups.filter { $0 != .all }), id: \.self) { filter in
                if let muscleGroup = filter.primaryMuscleGroup {
                    ForEach(viewModel.dataPoints) { point in
                        if let volume = point.muscleGroupVolumes[muscleGroup], volume > 0 {
                            LineMark(
                                x: .value("日期", point.date),
                                y: .value("容量", volume)
                            )
                            .foregroundStyle(by: .value("肌群", filter.rawValue))
                            .symbol(Circle())
                        }
                    }
                }
            }
        }
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
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let volume = value.as(Double.self) {
                        Text(GlobalSettingsManager.shared.formatWeight(volume))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartLegend(position: .bottom, spacing: 8)
    }
    
    // MARK: - Muscle Group Filters
    private var muscleGroupFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MuscleGroupFilter.allCases) { filter in
                    FilterChip(
                        title: filter.rawValue,
                        isSelected: viewModel.selectedMuscleGroups.contains(filter),
                        color: getColor(for: filter)
                    ) {
                        viewModel.toggleMuscleGroup(filter)
                    }
                }
            }
        }
    }
    
    // MARK: - Stats Section
    private var statsSection: some View {
        HStack(spacing: 20) {
            VolumeStatItem(
                title: "平均容量",
                value: viewModel.formattedAverageVolume,
                icon: "chart.bar.fill",
                color: .blue
            )
            
            Divider()
            
            VolumeStatItem(
                title: "最高容量",
                value: viewModel.formattedHighestVolume,
                icon: "arrow.up.circle.fill",
                color: .green
            )
            
            Divider()
            
            VolumeStatItem(
                title: "數據點",
                value: "\(viewModel.dataPoints.count)",
                icon: "circle.grid.3x3.fill",
                color: .orange
            )
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Helper Methods
    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        } else {
            return String(format: "%.0f", volume)
        }
    }
    
    private func getColor(for filter: MuscleGroupFilter) -> Color {
        switch filter.color {
        case "blue": return .blue
        case "red": return .red
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "yellow": return .yellow
        default: return .gray
        }
    }
}

// MARK: - Filter Chip
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? color.opacity(0.2) : Color(.secondarySystemBackground))
            .foregroundColor(isSelected ? color : .primary)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1.5)
            )
        }
    }
}

// MARK: - Stat Item
private struct VolumeStatItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview
#Preview {
    ScrollView {
        VolumeChartView()
            .padding()
    }
}
