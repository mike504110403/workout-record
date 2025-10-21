import SwiftUI

struct StatsView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented control for different stat categories
                Picker("統計類別", selection: $selectedTab) {
                    Text("體重").tag(0)
                    Text("訓練").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content based on selected tab
                TabView(selection: $selectedTab) {
                    // 使用完整的體重記錄頁面
                    BodyWeightView()
                        .tag(0)
                    
                    WorkoutStatsView()
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("數據")
        }
    }
}

struct WorkoutStatsView: View {
    @StateObject private var dashboardViewModel = DashboardViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 容量趨勢圖
                VolumeChartView()
                    .padding(.horizontal)
                
                // PR 快速入口
                NavigationLink {
                    PRView()
                } label: {
                    HStack {
                        Image(systemName: "trophy.fill")
                            .foregroundColor(.orange)
                        
                        Text("個人記錄 (PR)")
                            .font(.headline)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
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
                .buttonStyle(.plain)
                .padding(.horizontal)
                
                // 本週統計
                VStack(alignment: .leading, spacing: 12) {
                    Text("本週統計")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                    
                    HStack(spacing: 12) {
                        WorkoutStatCard(
                            title: "訓練次數",
                            value: "\(dashboardViewModel.weekWorkoutCount)",
                            unit: "次",
                            icon: "dumbbell.fill",
                            color: .blue
                        )
                        
                        WorkoutStatCard(
                            title: "總容量",
                            value: String(format: "%.0f", dashboardViewModel.weekTotalVolume),
                            unit: "kg",
                            icon: "chart.bar.fill",
                            color: .green
                        )
                    }
                    .padding(.horizontal)
                }
                
                // 最近訓練
                VStack(alignment: .leading, spacing: 12) {
                    Text("最近訓練")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                    
                    if dashboardViewModel.recentWorkouts.isEmpty {
                        EmptyWorkoutStatsView()
                            .padding()
                    } else {
                        ForEach(dashboardViewModel.recentWorkouts) { workout in
                            WorkoutStatsRow(workout: workout)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .onAppear {
            dashboardViewModel.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutCompleted)) { _ in
            dashboardViewModel.refresh()
        }
    }
}

// MARK: - Supporting Views

struct WorkoutStatCard: View {
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

struct WorkoutStatsRow: View {
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

struct EmptyWorkoutStatsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.walk")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text("尚無訓練記錄")
                .font(.headline)
            
            Text("開始你的第一次訓練吧！")
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

#Preview {
    StatsView()
}
