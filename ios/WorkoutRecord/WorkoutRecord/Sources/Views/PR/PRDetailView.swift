import SwiftUI
import Charts

struct PRDetailView: View {
    let summary: PRSummary
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 當前 PR 卡片
                if let currentPR = summary.currentPR {
                    currentPRCard(currentPR)
                }
                
                // PR 進步趨勢圖
                if summary.prHistory.count > 1 {
                    prProgressChart
                }
                
                // PR 歷史記錄
                if !summary.prHistory.isEmpty {
                    prHistorySection
                }
            }
            .padding()
        }
        .navigationTitle(summary.exerciseName)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Current PR Card
    private func currentPRCard(_ pr: PersonalRecord) -> some View {
        VStack(spacing: 16) {
            // 標題
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundColor(.orange)
                Text("當前 PR")
                    .font(.headline)
                Spacer()
            }
            
            // PR 數據
            HStack(spacing: 20) {
                Spacer()
                
                VStack(spacing: 8) {
                    Text(String(format: "%.1f", pr.weight))
                        .font(.system(size: 36, weight: .bold))
                    Text("kg")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("重量")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 8) {
                    Text("\(pr.reps)")
                        .font(.system(size: 36, weight: .bold))
                    Text("次")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("次數")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 8) {
                    Text(String(format: "%.1f", pr.oneRepMax))
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.blue)
                    Text("kg")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("1RM")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Divider()
            
            // 達成日期
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.secondary)
                Text("達成日期：")
                    .foregroundColor(.secondary)
                Text(pr.achievedAt.formatted(date: .long, time: .omitted))
                    .fontWeight(.medium)
                Spacer()
            }
            .font(.subheadline)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Progress Chart
    private var prProgressChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("進步趨勢")
                .font(.headline)
            
            Chart {
                ForEach(summary.prHistory.sorted(by: { $0.achievedAt < $1.achievedAt })) { pr in
                    LineMark(
                        x: .value("日期", pr.achievedAt),
                        y: .value("1RM", pr.oneRepMax)
                    )
                    .foregroundStyle(.blue)
                    .symbol(Circle())
                    
                    PointMark(
                        x: .value("日期", pr.achievedAt),
                        y: .value("1RM", pr.oneRepMax)
                    )
                    .foregroundStyle(.blue)
                }
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
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let oneRM = value.as(Double.self) {
                            Text(String(format: "%.0f", oneRM))
                                .font(.caption2)
                        }
                    }
                }
            }
            
            // 進步統計
            if let firstPR = summary.prHistory.last,
               let latestPR = summary.prHistory.first {
                let improvement = latestPR.oneRepMax - firstPR.oneRepMax
                let percentage = (improvement / firstPR.oneRepMax) * 100
                
                HStack {
                    Image(systemName: "arrow.up.right")
                        .foregroundColor(.green)
                    
                    Text("總進步：")
                        .foregroundColor(.secondary)
                    
                    Text(String(format: "+%.1f kg (%.1f%%)", improvement, percentage))
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                    
                    Spacer()
                }
                .font(.subheadline)
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - History Section
    private var prHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("歷史記錄")
                .font(.headline)
            
            ForEach(summary.prHistory) { pr in
                PRHistoryRow(pr: pr, isCurrent: pr.id == summary.currentPR?.id)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - PR History Row
private struct PRHistoryRow: View {
    let pr: PersonalRecord
    let isCurrent: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // 日期
            VStack(alignment: .leading, spacing: 2) {
                Text(pr.achievedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline)
                    .fontWeight(isCurrent ? .semibold : .regular)
                
                if isCurrent {
                    Text("當前 PR")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .frame(width: 80, alignment: .leading)
            
            Divider()
            
            // 數據
            HStack(spacing: 24) {
                DataItem(label: "重量", value: String(format: "%.1f kg", pr.weight))
                DataItem(label: "次數", value: "\(pr.reps) 次")
                DataItem(label: "1RM", value: String(format: "%.1f kg", pr.oneRepMax), highlight: true)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isCurrent ? Color.orange.opacity(0.1) : Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }
    
    private struct DataItem: View {
        let label: String
        let value: String
        var highlight: Bool = false
        
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.caption)
                    .fontWeight(highlight ? .semibold : .regular)
                    .foregroundColor(highlight ? .blue : .primary)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        PRDetailView(
            summary: PRSummary(
                exerciseId: UUID(),
                exerciseName: "槓鈴臥推",
                primaryMuscleGroup: .chest,
                currentPR: PersonalRecord(
                    userId: UUID(),
                    exerciseId: UUID(),
                    weight: 100,
                    reps: 8,
                    oneRepMax: 125,
                    achievedAt: Date()
                ),
                prHistory: [
                    PersonalRecord(
                        userId: UUID(),
                        exerciseId: UUID(),
                        weight: 100,
                        reps: 8,
                        oneRepMax: 125,
                        achievedAt: Date()
                    ),
                    PersonalRecord(
                        userId: UUID(),
                        exerciseId: UUID(),
                        weight: 95,
                        reps: 8,
                        oneRepMax: 119,
                        achievedAt: Date().addingTimeInterval(-7*24*60*60)
                    ),
                    PersonalRecord(
                        userId: UUID(),
                        exerciseId: UUID(),
                        weight: 90,
                        reps: 8,
                        oneRepMax: 112,
                        achievedAt: Date().addingTimeInterval(-14*24*60*60)
                    )
                ]
            )
        )
    }
}

