import SwiftUI
import Charts

struct VolumeChartView: View {
    let data: [VolumeTrendPoint]
    let chartType: ChartType
    let timeRange: TimeRange
    
    enum ChartType {
        case line, bar
    }
    
    enum TimeRange {
        case week, month, threeMonths, year
        
        var displayName: String {
            switch self {
            case .week: return "本週"
            case .month: return "本月"
            case .threeMonths: return "三個月"
            case .year: return "本年"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Chart title
            HStack {
                Text("訓練容量趨勢")
                    .font(.headline)
                
                Spacer()
                
                Text(VolumeCalculator.formatVolume(totalVolume))
                    .font(.headline)
                    .foregroundColor(.blue)
            }
            
            // Chart
            Chart(data) { point in
                if chartType == .bar {
                    BarMark(
                        x: .value("日期", point.date),
                        y: .value("容量", point.volume)
                    )
                    .foregroundStyle(volumeGradient)
                    .cornerRadius(4)
                } else {
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("容量", point.volume)
                    )
                    .foregroundStyle(Color.orange.gradient)
                    .interpolationMethod(.catmullRom)
                    .symbol {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                    }
                    
                    AreaMark(
                        x: .value("日期", point.date),
                        y: .value("容量", point.volume)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.3), Color.orange.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
            }
            .frame(height: 200)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let intValue = value.as(Double.self) {
                            Text(formatVolume(intValue))
                                .font(.caption)
                        }
                    }
                }
            }
            
            // Statistics
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("平均")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(VolumeCalculator.formatVolume(averageVolume))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("最高")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(VolumeCalculator.formatVolume(maxVolume))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("訓練次數")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(data.count) 次")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Computed Properties
    private var totalVolume: Double {
        data.reduce(0) { $0 + $1.volume }
    }
    
    private var averageVolume: Double {
        guard !data.isEmpty else { return 0 }
        return totalVolume / Double(data.count)
    }
    
    private var maxVolume: Double {
        data.map { $0.volume }.max() ?? 0
    }
    
    private var volumeGradient: LinearGradient {
        LinearGradient(
            colors: [Color.orange, Color.orange.opacity(0.7)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        } else {
            return String(format: "%.0f", volume)
        }
    }
}

// MARK: - Volume Trend Point
struct VolumeTrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let volume: Double
    let workoutCount: Int?
    
    init(date: Date, volume: Double, workoutCount: Int? = nil) {
        self.date = date
        self.volume = volume
        self.workoutCount = workoutCount
    }
}

#Preview {
    let mockData = (0..<14).map { day in
        VolumeTrendPoint(
            date: Calendar.current.date(byAdding: .day, value: -day, to: Date())!,
            volume: Double.random(in: 3000...6000),
            workoutCount: Int.random(in: 1...2)
        )
    }.reversed()
    
    return VolumeChartView(
        data: Array(mockData),
        chartType: .bar,
        timeRange: .week
    )
    .padding()
}

