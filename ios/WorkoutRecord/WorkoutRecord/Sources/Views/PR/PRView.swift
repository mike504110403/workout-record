import SwiftUI

struct PRView: View {
    @StateObject private var viewModel = PRViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // 肌群篩選器
            if !viewModel.muscleGroups.isEmpty {
                muscleGroupFilter
                    .padding()
            }
            
            // PR 列表
            if viewModel.isLoading {
                ProgressView("載入中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredSummaries.isEmpty {
                emptyStateView
            } else {
                prListView
            }
        }
        .navigationTitle("個人記錄")
        .onAppear {
            viewModel.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutCompleted)) { _ in
            viewModel.refresh()
        }
    }
    
    // MARK: - Muscle Group Filter
    private var muscleGroupFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "全部" 選項
                FilterButton(
                    title: "全部",
                    isSelected: viewModel.selectedMuscleGroup == nil
                ) {
                    viewModel.selectMuscleGroup(nil)
                }
                
                // 各肌群選項
                ForEach(viewModel.muscleGroups, id: \.self) { group in
                    FilterButton(
                        title: group.displayName,
                        isSelected: viewModel.selectedMuscleGroup == group
                    ) {
                        viewModel.selectMuscleGroup(group)
                    }
                }
            }
        }
    }
    
    // MARK: - PR List
    private var prListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.filteredSummaries) { summary in
                    NavigationLink {
                        PRDetailView(summary: summary)
                    } label: {
                        PRCard(summary: summary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .refreshable {
            viewModel.refresh()
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("尚無 PR 記錄")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("完成訓練後這裡會顯示你的個人最佳記錄")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Filter Button
private struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(.secondarySystemBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
    }
}

// MARK: - PR Card
private struct PRCard: View {
    let summary: PRSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 動作名稱和肌群
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.exerciseName)
                        .font(.headline)
                    
                    if let muscleGroup = summary.primaryMuscleGroup {
                        Text(muscleGroup.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            
            Divider()
            
            // PR 數據
            if let pr = summary.currentPR {
                HStack(spacing: 24) {
                    PRStatItem(
                        label: "PR 重量",
                        value: String(format: "%.1f", pr.weight),
                        unit: "kg"
                    )
                    
                    PRStatItem(
                        label: "次數",
                        value: "\(pr.reps)",
                        unit: "次"
                    )
                    
                    PRStatItem(
                        label: "1RM 估算",
                        value: String(format: "%.1f", pr.oneRepMax),
                        unit: "kg"
                    )
                }
                
                // 達成日期
                HStack {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(pr.achievedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if summary.prHistory.count > 1 {
                        Text("\(summary.prHistory.count) 次記錄")
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

// MARK: - PR Stat Item
private struct PRStatItem: View {
    let label: String
    let value: String
    let unit: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        PRView()
    }
}

