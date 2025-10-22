import SwiftUI

/// 通用統計卡片元件
/// 用於顯示各種統計數據，支持趨勢指示
struct StatCardView: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    var trend: TrendDirection? = nil
    var showDivider: Bool = false
    
    enum TrendDirection {
        case up, down, neutral
        
        var icon: String {
            switch self {
            case .up: return "arrow.up"
            case .down: return "arrow.down"
            case .neutral: return "minus"
            }
        }
        
        var color: Color {
            switch self {
            case .up: return .green
            case .down: return .red
            case .neutral: return .gray
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 標題與圖示
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // 數值與單位
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let trend = trend {
                    Image(systemName: trend.icon)
                        .font(.caption)
                        .foregroundColor(trend.color)
                }
                
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                
                Text(unit)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

#Preview {
    HStack(spacing: 12) {
        StatCardView(
            title: "訓練次數",
            value: "12",
            unit: "次",
            icon: "dumbbell.fill",
            color: .blue
        )
        
        StatCardView(
            title: "變化",
            value: "2.5",
            unit: "kg",
            icon: "scalemass.fill",
            color: .green,
            trend: .down
        )
    }
    .padding()
}

