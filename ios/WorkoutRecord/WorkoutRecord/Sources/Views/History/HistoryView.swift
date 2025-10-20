import SwiftUI

struct HistoryView: View {
    @State private var viewMode: ViewMode = .list
    
    enum ViewMode {
        case calendar
        case list
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // View mode picker
                Picker("檢視模式", selection: $viewMode) {
                    Label("列表", systemImage: "list.bullet").tag(ViewMode.list)
                    Label("日曆", systemImage: "calendar").tag(ViewMode.calendar)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content based on view mode
                if viewMode == .list {
                    HistoryListView()
                } else {
                    HistoryCalendarView()
                }
            }
            .navigationDestination(for: WorkoutSummary.self) { workout in
                WorkoutDetailView(workout: workout)
            }
            .navigationTitle("歷史記錄")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        // TODO: Show filter options
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }
}

struct HistoryListView: View {
    // Mock data
    let mockWorkouts: [WorkoutSummary] = [
        WorkoutSummary(id: UUID(), date: Date(), duration: 75, totalVolume: 5230, totalSets: 24, exercisesCount: 6),
        WorkoutSummary(id: UUID(), date: Date().addingTimeInterval(-86400), duration: 80, totalVolume: 4800, totalSets: 22, exercisesCount: 5),
        WorkoutSummary(id: UUID(), date: Date().addingTimeInterval(-172800), duration: 70, totalVolume: 4200, totalSets: 20, exercisesCount: 5),
        WorkoutSummary(id: UUID(), date: Date().addingTimeInterval(-259200), duration: 85, totalVolume: 5020, totalSets: 26, exercisesCount: 6),
    ]
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(mockWorkouts) { workout in
                    NavigationLink(value: workout) {
                        WorkoutHistoryCard(workout: workout)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
}

struct HistoryCalendarView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Placeholder for calendar view
                Rectangle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(height: 300)
                    .cornerRadius(12)
                    .overlay {
                        VStack {
                            Image(systemName: "calendar")
                                .font(.system(size: 40))
                            Text("日曆檢視")
                            Text("開發中...")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    .padding()
            }
        }
    }
}

struct WorkoutHistoryCard: View {
    let workout: WorkoutSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.headline)
                    
                    Text(workout.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(String(format: "%.0f kg", workout.totalVolume))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            Divider()
            
            HStack(spacing: 20) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text("\(workout.duration) 分鐘")
                        .font(.caption)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.caption)
                    Text("\(workout.exercisesCount) 個動作")
                        .font(.caption)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar")
                        .font(.caption)
                    Text("\(workout.totalSets) 組")
                        .font(.caption)
                }
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// WorkoutDetailView is defined in WorkoutDetailView.swift
// Removed duplicate definition

#Preview {
    HistoryView()
}

