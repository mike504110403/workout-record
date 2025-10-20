import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @StateObject private var bodyWeightViewModel = BodyWeightViewModel()
    @State private var showBodyWeightSheet = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Today Overview Section
                    todayOverviewSection
                    
                    // Quick Actions Section
                    quickActionsSection
                    
                    // This Week Stats Section
                    weekStatsSection
                    
                    // Recent Workouts Section
                    recentWorkoutsSection
                }
                .padding()
            }
            .navigationTitle("首頁")
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showBodyWeightSheet) {
                AddBodyWeightSheet(viewModel: bodyWeightViewModel)
            }
        }
    }
    
    // MARK: - Today Overview
    private var todayOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日概覽")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                // Today's workout card
                if let todayWorkout = viewModel.todayWorkout {
                    TodayWorkoutCard(workout: todayWorkout)
                } else {
                    NoWorkoutTodayCard()
                }
                
                // Body weight trend mini chart (placeholder)
                BodyWeightMiniCard(currentWeight: viewModel.currentWeight)
            }
        }
    }
    
    // MARK: - Quick Actions
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快速操作")
                .font(.headline)
                .padding(.horizontal)
            
            HStack(spacing: 12) {
                QuickActionButton(
                    icon: "scalemass.fill",
                    title: "記錄體重",
                    color: .blue
                ) {
                    showBodyWeightSheet = true
                }
                
                Button {
                    // 發送通知切換到訓練 Tab
                    NotificationCenter.default.post(name: .switchToWorkoutTab, object: nil)
                } label: {
                    QuickActionLinkButton(
                        icon: "figure.strengthtraining.traditional",
                        title: "開始訓練",
                        color: .green
                    )
                }
                .buttonStyle(.plain)
                
                Button {
                    // 發送通知切換到數據 Tab
                    NotificationCenter.default.post(name: .switchToStatsTab, object: nil)
                } label: {
                    QuickActionLinkButton(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "查看進度",
                        color: .orange
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - This Week Stats
    private var weekStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本週統計")
                .font(.headline)
                .padding(.horizontal)
            
            HStack(spacing: 12) {
                StatCard(
                    title: "訓練次數",
                    value: "\(viewModel.weekWorkoutCount)",
                    unit: "次",
                    icon: "dumbbell.fill",
                    color: .blue
                )
                
                StatCard(
                    title: "總容量",
                    value: String(format: "%.0f", viewModel.weekTotalVolume),
                    unit: "kg",
                    icon: "chart.bar.fill",
                    color: .green
                )
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Recent Workouts
    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近訓練")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    // 發送通知切換到歷史 Tab
                    NotificationCenter.default.post(name: .switchToHistoryTab, object: nil)
                } label: {
                    Text("查看全部")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            
            VStack(spacing: 8) {
                ForEach(viewModel.recentWorkouts) { workout in
                    RecentWorkoutRow(workout: workout)
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct TodayWorkoutCard: View {
    let workout: WorkoutSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("今日已完成訓練")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("訓練時長")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(workout.duration) 分鐘")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("總容量")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.0f kg", workout.totalVolume))
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("組數")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(workout.totalSets)")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }
}

struct NoWorkoutTodayCard: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.walk")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text("今日尚未訓練")
                .font(.headline)
            
            Text("點擊下方「開始訓練」開始記錄")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }
}

struct BodyWeightMiniCard: View {
    let currentWeight: Double?
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("當前體重")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let weight = currentWeight {
                    Text(String(format: "%.1f kg", weight))
                        .font(.title2)
                        .fontWeight(.semibold)
                } else {
                    Text("尚未記錄")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Placeholder for mini chart
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 30))
                .foregroundColor(.blue)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(color)
                    .cornerRadius(12)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
    }
}

struct QuickActionLinkButton: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(color)
                .cornerRadius(12)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
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

struct RecentWorkoutRow: View {
    let workout: WorkoutSummary
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(workout.exercisesCount) 個動作 • \(workout.totalSets) 組")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.0f kg", workout.totalVolume))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text("\(workout.duration) 分鐘")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }
}

#Preview {
    DashboardView()
}

