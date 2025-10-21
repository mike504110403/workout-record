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
    @StateObject private var viewModel = HistoryViewModel()
    
    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("載入中...")
            } else if viewModel.workouts.isEmpty {
                EmptyHistoryView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.workouts) { workout in
                            NavigationLink(value: workout) {
                                WorkoutHistoryCard(workout: workout)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    viewModel.deleteWorkout(workout)
                                } label: {
                                    Label("刪除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding()
                }
                .refreshable {
                    viewModel.refresh()
                }
            }
        }
        .onAppear {
            viewModel.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutCompleted)) { _ in
            viewModel.refresh()
        }
    }
}

struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("尚無訓練記錄")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("完成你的第一次訓練吧！")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HistoryCalendarView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @State private var selectedMonth = Date()
    @State private var selectedDate: Date?
    
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 月份選擇器
                monthPicker
                
                // 日曆網格
                calendarGrid
                
                // 選中日期的訓練列表
                if let selected = selectedDate {
                    selectedDateWorkouts(for: selected)
                }
            }
            .padding()
        }
        .onAppear {
            viewModel.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutCompleted)) { _ in
            viewModel.refresh()
        }
    }
    
    private var monthPicker: some View {
        HStack {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            
            Spacer()
            
            Text(selectedMonth.formatted(.dateTime.year().month(.wide)))
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
            
            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal)
    }
    
    private var calendarGrid: some View {
        VStack(spacing: 12) {
            // 星期標題
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // 日期網格
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(getDaysInMonth(), id: \.self) { date in
                    if let date = date {
                        dayCell(for: date)
                    } else {
                        Color.clear
                            .frame(height: 50)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
    
    private func dayCell(for date: Date) -> some View {
        let workoutCount = getWorkoutCount(for: date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate ?? Date.distantPast)
        let isToday = calendar.isDateInToday(date)
        
        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.body)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundColor(isSelected ? .white : (isToday ? .blue : .primary))
                
                if workoutCount > 0 {
                    Circle()
                        .fill(isSelected ? .white : .blue)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                isSelected ?
                    Color.blue :
                    (isToday ? Color.blue.opacity(0.1) : Color.clear)
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
    
    private func selectedDateWorkouts(for date: Date) -> some View {
        let workouts = getWorkouts(for: date)
        
        return VStack(alignment: .leading, spacing: 12) {
            Text(date.formatted(date: .long, time: .omitted))
                .font(.headline)
                .padding(.horizontal)
            
            if workouts.isEmpty {
                Text("當天無訓練記錄")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(workouts) { workout in
                    NavigationLink(value: workout) {
                        WorkoutHistoryCard(workout: workout)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private func changeMonth(by months: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: months, to: selectedMonth) {
            selectedMonth = newMonth
            selectedDate = nil
        }
    }
    
    private func getDaysInMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedMonth),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start) else {
            return []
        }
        
        var days: [Date?] = []
        
        // 從月初所在週的週日開始
        var date = monthFirstWeek.start
        
        while true {
            let isInCurrentMonth = calendar.isDate(date, equalTo: selectedMonth, toGranularity: .month)
            
            if isInCurrentMonth {
                days.append(date)
            } else if !days.isEmpty {
                // 如果已經開始添加日期，且當前日期不在當月，則填充空白
                days.append(nil)
            } else {
                // 月初前的空白
                days.append(nil)
            }
            
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = nextDate
            
            // 檢查是否已經到達下個月的週六後
            if !isInCurrentMonth && days.count > 28 && calendar.component(.weekday, from: date) == 1 {
                break
            }
        }
        
        return days
    }
    
    private func getWorkoutCount(for date: Date) -> Int {
        return viewModel.workouts.filter { workout in
            calendar.isDate(workout.date, inSameDayAs: date)
        }.count
    }
    
    private func getWorkouts(for date: Date) -> [WorkoutSummary] {
        return viewModel.workouts.filter { workout in
            calendar.isDate(workout.date, inSameDayAs: date)
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

