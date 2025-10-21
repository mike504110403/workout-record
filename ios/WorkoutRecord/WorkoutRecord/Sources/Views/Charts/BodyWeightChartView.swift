import SwiftUI
import Charts

struct BodyWeightChartView: View {
    let data: [BodyWeightTrendPoint]
    let targetWeight: Double?
    let timeRange: TimeRange
    
    enum TimeRange {
        case week, month, threeMonths, year
        
        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .threeMonths: return 90
            case .year: return 365
            }
        }
        
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
            Text("體重趨勢")
                .font(.headline)
            
            // Chart
            Chart {
                // Weight line
                ForEach(data) { point in
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("體重", point.weight)
                    )
                    .foregroundStyle(Color.blue.gradient)
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("日期", point.date),
                        y: .value("體重", point.weight)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                
                // Target weight line
                if let target = targetWeight {
                    RuleMark(
                        y: .value("目標", target)
                    )
                    .foregroundStyle(Color.green)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("目標: \(String(format: "%.1f", target)) kg")
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                    }
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
                AxisMarks(position: .leading)
            }
            
            // Legend
            HStack(spacing: 20) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                    Text("實際體重")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if targetWeight != nil {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: 12, height: 2)
                        Text("目標體重")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

#Preview {
    let mockData = (0..<30).map { day in
        BodyWeightTrendPoint(
            date: Calendar.current.date(byAdding: .day, value: -day, to: Date())!,
            weight: 75.0 + Double.random(in: -2...2)
        )
    }.reversed()
    
    return BodyWeightChartView(
        data: Array(mockData),
        targetWeight: nil,
        timeRange: .month
    )
    .padding()
}

