import SwiftUI
import Charts
import Combine

/// 修復自定義動作圖表的視圖
struct FixedExerciseChartView: View {
    @StateObject private var viewModel = FixedExerciseChartViewModel()
    @State private var selectedTimeRange: TimeRange = .month
    @State private var selectedExercise: Exercise?
    
    enum TimeRange: String, CaseIterable {
        case week = "週"
        case month = "月"
        case year = "年"
        
        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .year: return 365
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 篩選器
                filterSection
                
                // 圖表區域
                chartSection
                
                // 動作列表
                exerciseListSection
            }
            .navigationTitle("動作分析")
            .onAppear {
                viewModel.loadData()
            }
        }
    }
    
    // MARK: - Filter Section
    
    private var filterSection: some View {
        VStack(spacing: 16) {
            // 時間範圍選擇器
            Picker("時間範圍", selection: $selectedTimeRange) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedTimeRange) { _ in
                viewModel.updateTimeRange(selectedTimeRange)
            }
            
            // 動作選擇器
            if !viewModel.exercises.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.exercises) { exercise in
                            ExerciseFilterButton(
                                exercise: exercise,
                                isSelected: selectedExercise?.id == exercise.id
                            ) {
                                selectedExercise = exercise
                                viewModel.selectExercise(exercise)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }
    
    // MARK: - Chart Section
    
    private var chartSection: some View {
        VStack(spacing: 16) {
            if let exercise = selectedExercise ?? viewModel.exercises.first {
                // 圖表標題
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text(exercise.isSystem ? "系統動作" : "自定義動作")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // 動作類型標籤
                    Text(exercise.category?.name ?? "未知分類")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                }
                
                // 圖表
                if #available(iOS 16.0, *) {
                    Chart(viewModel.chartData) { dataPoint in
                        LineMark(
                            x: .value("日期", dataPoint.date),
                            y: .value("重量", dataPoint.weight)
                        )
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        
                        AreaMark(
                            x: .value("日期", dataPoint.date),
                            y: .value("重量", dataPoint.weight)
                        )
                        .foregroundStyle(.blue.opacity(0.1))
                    }
                    .frame(height: 200)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: selectedTimeRange == .week ? 1 : 7)) { value in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let weight = value.as(Double.self) {
                                    Text("\(Int(weight)) kg")
                                }
                            }
                        }
                    }
                } else {
                    // iOS 15 及以下版本的替代圖表
                    LegacyChartView(data: viewModel.chartData)
                        .frame(height: 200)
                }
                
                // 統計資訊
                statisticsSection(for: exercise)
            } else {
                // 空狀態
                VStack(spacing: 16) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("尚無訓練數據")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("開始訓練後即可查看動作分析圖表")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(height: 200)
            }
        }
        .padding()
    }
    
    // MARK: - Statistics Section
    
    private func statisticsSection(for exercise: Exercise) -> some View {
        VStack(spacing: 12) {
            Text("統計資訊")
                .font(.headline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                StatCard(
                    title: "最高重量",
                    value: "\(Int(viewModel.maxWeight)) kg",
                    icon: "arrow.up",
                    color: .red
                )
                
                StatCard(
                    title: "平均重量",
                    value: "\(Int(viewModel.averageWeight)) kg",
                    icon: "equal",
                    color: .blue
                )
                
                StatCard(
                    title: "訓練次數",
                    value: "\(viewModel.workoutCount)",
                    icon: "number",
                    color: .green
                )
                
                StatCard(
                    title: "進步幅度",
                    value: String(format: "%.1f", viewModel.improvementPercentage) + "%",
                    icon: "chart.line.uptrend.xyaxis",
                    color: .orange
                )
            }
        }
    }
    
    // MARK: - Exercise List Section
    
    private var exerciseListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("所有動作")
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.horizontal)
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.exercises) { exercise in
                        ExerciseListItem(
                            exercise: exercise,
                            isSelected: selectedExercise?.id == exercise.id,
                            workoutCount: viewModel.getWorkoutCount(for: exercise),
                            maxWeight: viewModel.getMaxWeight(for: exercise)
                        ) {
                            selectedExercise = exercise
                            viewModel.selectExercise(exercise)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Supporting Views

struct ExerciseFilterButton: View {
    let exercise: Exercise
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(exercise.name)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(.secondarySystemBackground))
                .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}

struct ExerciseListItem: View {
    let exercise: Exercise
    let isSelected: Bool
    let workoutCount: Int
    let maxWeight: Double
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // 動作圖標
                Image(systemName: exercise.isSystem ? "figure.strengthtraining.traditional" : "plus.circle")
                    .foregroundColor(exercise.isSystem ? .blue : .green)
                    .frame(width: 20)
                
                // 動作資訊
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(exercise.isSystem ? "系統動作" : "自定義動作")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 統計資訊
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(workoutCount) 次")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    
                    Text("\(Int(maxWeight)) kg")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // 選擇指示器
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// StatCard 定義已移至 Views/Components/StatCardView.swift

// MARK: - Legacy Chart View (for iOS 15 and below)

struct LegacyChartView: View {
    let data: [ChartDataPoint]
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let maxWeight = data.map(\.weight).max() ?? 1
            let minWeight = data.map(\.weight).min() ?? 0
            let weightRange = maxWeight - minWeight
            
            ZStack {
                // 背景網格
                Path { path in
                    for i in 0...4 {
                        let y = height * CGFloat(i) / 4
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                }
                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                
                // 數據線
                if data.count > 1 {
                    Path { path in
                        for (index, point) in data.enumerated() {
                            let x = width * CGFloat(index) / CGFloat(data.count - 1)
                            let y = height - (height * CGFloat(point.weight - minWeight) / CGFloat(weightRange))
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.blue, lineWidth: 2)
                }
                
                // 數據點
                ForEach(Array(data.enumerated()), id: \.offset) { index, point in
                    let x = width * CGFloat(index) / CGFloat(data.count - 1)
                    let y = height - (height * CGFloat(point.weight - minWeight) / CGFloat(weightRange))
                    
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                        .position(x: x, y: y)
                }
            }
        }
    }
}

// MARK: - Chart Data Point

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let weight: Double
    let reps: Int
    let exerciseId: UUID
    let exerciseName: String
    let isCustomExercise: Bool
}

// MARK: - View Model

@MainActor
class FixedExerciseChartViewModel: ObservableObject {
    @Published var exercises: [Exercise] = []
    @Published var chartData: [ChartDataPoint] = []
    @Published var maxWeight: Double = 0
    @Published var averageWeight: Double = 0
    @Published var workoutCount: Int = 0
    @Published var improvementPercentage: Double = 0
    
    private let workoutRepository = WorkoutRepository()
    private let exerciseRepository = ExerciseRepository()
    private var selectedExercise: Exercise?
    private var timeRange: FixedExerciseChartView.TimeRange = .month
    
    func loadData() {
        loadExercises()
        Task {
            await updateChartData()
        }
    }
    
    private func loadExercises() {
        do {
            // 載入所有動作（系統 + 自定義）
            let systemExercises = try exerciseRepository.fetchAll()
            let customExercises = try exerciseRepository.getCustomExercises()
            
            exercises = systemExercises + customExercises
        } catch {
            print("❌ 載入動作失敗: \(error.localizedDescription)")
        }
    }
    
    func selectExercise(_ exercise: Exercise) {
        selectedExercise = exercise
        Task {
            await updateChartData()
        }
    }
    
    func updateTimeRange(_ range: FixedExerciseChartView.TimeRange) {
        timeRange = range
        Task {
            await updateChartData()
        }
    }
    
    private func updateChartData() async {
        guard let exercise = selectedExercise ?? exercises.first else {
            chartData = []
            return
        }
        
        do {
            let endDate = Date()
            let startDate = Calendar.current.date(byAdding: .day, value: -timeRange.days, to: endDate) ?? endDate
            
            let workouts = try workoutRepository.getAllWorkouts()
            
            // 篩選包含選中動作的訓練
            let relevantWorkouts = workouts.filter { workout in
                workout.exercises.contains { workoutExercise in
                    workoutExercise.exerciseId == exercise.id
                }
            }
            
            // 提取圖表數據
            var dataPoints: [ChartDataPoint] = []
            
            for workout in relevantWorkouts {
                for workoutExercise in workout.exercises {
                    if workoutExercise.exerciseId == exercise.id {
                        // 找到該動作的最佳組數（最高重量）
                        if let bestSet = workoutExercise.sets.max(by: { $0.weight < $1.weight }) {
                            let dataPoint = ChartDataPoint(
                                date: workout.startedAt,
                                weight: bestSet.weight,
                                reps: bestSet.reps,
                                exerciseId: exercise.id,
                                exerciseName: exercise.name,
                                isCustomExercise: !exercise.isSystem
                            )
                            dataPoints.append(dataPoint)
                        }
                    }
                }
            }
            
            // 按日期排序
            dataPoints.sort { $0.date < $1.date }
            
            await MainActor.run {
                chartData = dataPoints
                updateStatistics()
            }
        } catch {
            print("❌ 更新圖表數據失敗: \(error.localizedDescription)")
        }
    }
    
    private func updateStatistics() {
        guard !chartData.isEmpty else {
            maxWeight = 0
            averageWeight = 0
            workoutCount = 0
            improvementPercentage = 0
            return
        }
        
        maxWeight = chartData.map(\.weight).max() ?? 0
        averageWeight = chartData.map(\.weight).reduce(0, +) / Double(chartData.count)
        workoutCount = chartData.count
        
        // 計算進步幅度
        if chartData.count > 1 {
            let firstWeight = chartData.first?.weight ?? 0
            let lastWeight = chartData.last?.weight ?? 0
            if firstWeight > 0 {
                improvementPercentage = ((lastWeight - firstWeight) / firstWeight) * 100
            }
        }
    }
    
    func getWorkoutCount(for exercise: Exercise) -> Int {
        return chartData.filter { $0.exerciseId == exercise.id }.count
    }
    
    func getMaxWeight(for exercise: Exercise) -> Double {
        return chartData.filter { $0.exerciseId == exercise.id }.map(\.weight).max() ?? 0
    }
}

#Preview {
    FixedExerciseChartView()
}
