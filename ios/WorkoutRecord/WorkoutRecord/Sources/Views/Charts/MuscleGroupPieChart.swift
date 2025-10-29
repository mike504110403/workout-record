import SwiftUI
import Charts

struct MuscleGroupPieChart: View {
    let data: [MuscleGroupVolume]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("肌群容量分布")
                .font(.headline)
            
            // iOS 16 兼容的條形圖展示
            VStack(spacing: 12) {
                ForEach(data) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(colorForMuscleGroup(item.muscleGroup))
                                    .frame(width: 10, height: 10)
                                
                                Text(item.muscleGroup)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            
                            Spacer()
                            
                            Text("\(String(format: "%.0f", item.percentage))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(VolumeCalculator.formatVolume(item.volume))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 60, alignment: .trailing)
                        }
                        
                        // Progress bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 6)
                                    .cornerRadius(3)
                                
                                Rectangle()
                                    .fill(colorForMuscleGroup(item.muscleGroup))
                                    .frame(width: geometry.size.width * (item.percentage / 100), height: 6)
                                    .cornerRadius(3)
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private func colorForMuscleGroup(_ group: String) -> Color {
        let colors: [String: Color] = [
            "胸": .red,
            "背": .blue,
            "腿": .green,
            "肩": .orange,
            "手臂": .purple,
            "核心": .pink
        ]
        return colors[group] ?? .gray
    }
}

// MARK: - Muscle Group Volume
struct MuscleGroupVolume: Identifiable {
    let id = UUID()
    let muscleGroup: String
    let volume: Double
    let percentage: Double
    
    init(muscleGroup: String, volume: Double, percentage: Double) {
        self.muscleGroup = muscleGroup
        self.volume = volume
        self.percentage = percentage
    }
}

#Preview {
    let mockData = [
        MuscleGroupVolume(muscleGroup: "胸", volume: 5000, percentage: 30),
        MuscleGroupVolume(muscleGroup: "背", volume: 4200, percentage: 25),
        MuscleGroupVolume(muscleGroup: "腿", volume: 4000, percentage: 24),
        MuscleGroupVolume(muscleGroup: "肩", volume: 2000, percentage: 12),
        MuscleGroupVolume(muscleGroup: "手臂", volume: 1500, percentage: 9)
    ]
    
    return MuscleGroupPieChart(data: mockData)
        .padding()
}

