import SwiftUI
import Combine
import Foundation

/// 日曆計劃視圖
struct CalendarPlanningView: View {
    @StateObject private var viewModel = CalendarPlanningViewModel()
    @State private var selectedDate = Date()
    @State private var showAddPlanSheet = false
    @State private var showPlanDetailSheet = false
    @State private var selectedPlan: WorkoutPlan?
    
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 月份選擇器
                monthPicker
                
                // 日曆網格
                calendarGrid
                
                // 選中日期的計劃列表
                selectedDatePlans
            }
            .navigationTitle("訓練計劃")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddPlanSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddPlanSheet) {
                AddWorkoutPlanSheet(selectedDate: selectedDate) { plan in
                    viewModel.addPlan(plan)
                }
            }
            .sheet(isPresented: $showPlanDetailSheet) {
                if let plan = selectedPlan {
                    WorkoutPlanDetailView(plan: plan)
                }
            }
            .onAppear {
                viewModel.loadPlans()
            }
        }
    }
    
    // MARK: - Month Picker
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
            
            Text(selectedDate.formatted(.dateTime.year().month(.wide)))
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
        .padding()
    }
    
    // MARK: - Calendar Grid
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
    
    // MARK: - Day Cell
    private func dayCell(for date: Date) -> some View {
        let plans = getPlans(for: date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        
        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.body)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundColor(isSelected ? .white : (isToday ? .blue : .primary))
                
                if !plans.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(plans.prefix(3)) { plan in
                            Circle()
                                .fill(plan.type.color)
                                .frame(width: 6, height: 6)
                        }
                        if plans.count > 3 {
                            Text("+")
                                .font(.caption2)
                                .foregroundColor(isSelected ? .white : .secondary)
                        }
                    }
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
    
    // MARK: - Selected Date Plans
    private var selectedDatePlans: some View {
        let plans = getPlans(for: selectedDate)
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedDate.formatted(date: .long, time: .omitted))
                    .font(.headline)
                
                Spacer()
                
                Button {
                    showAddPlanSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            
            if plans.isEmpty {
                EmptyPlansView(selectedDate: selectedDate)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(plans) { plan in
                            WorkoutPlanCard(plan: plan) {
                                selectedPlan = plan
                                showPlanDetailSheet = true
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private func changeMonth(by months: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: months, to: selectedDate) {
            selectedDate = newMonth
        }
    }
    
    private func getDaysInMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start) else {
            return []
        }
        
        var days: [Date?] = []
        var date = monthFirstWeek.start
        
        while true {
            let isInCurrentMonth = calendar.isDate(date, equalTo: selectedDate, toGranularity: .month)
            
            if isInCurrentMonth {
                days.append(date)
            } else if !days.isEmpty {
                days.append(nil)
            } else {
                days.append(nil)
            }
            
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = nextDate
            
            if !isInCurrentMonth && days.count > 28 && calendar.component(.weekday, from: date) == 1 {
                break
            }
        }
        
        return days
    }
    
    private func getPlans(for date: Date) -> [WorkoutPlan] {
        return viewModel.plans.filter { plan in
            calendar.isDate(plan.scheduledDate, inSameDayAs: date)
        }
    }
}

// MARK: - Supporting Views

struct EmptyPlansView: View {
    let selectedDate: Date
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("當天無訓練計劃")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("點擊右上角 + 號新增計劃")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct WorkoutPlanCard: View {
    let plan: WorkoutPlan
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(plan.type.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(plan.scheduledDate.formatted(date: .omitted, time: .shortened))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Text("\(plan.estimatedDuration) 分鐘")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if !plan.exercises.isEmpty {
                    HStack {
                        Text("\(plan.exercises.count) 個動作")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("預估容量: \(Int(plan.estimatedVolume)) kg")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add Workout Plan Sheet

struct AddWorkoutPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selectedDate: Date
    let onSave: (WorkoutPlan) -> Void
    
    @State private var planName = ""
    @State private var planType: WorkoutPlanType = .strength
    @State private var scheduledTime = Date()
    @State private var estimatedDuration = 60
    @State private var selectedTemplate: TemplateInfo?
    @State private var showTemplatePicker = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("基本資訊") {
                    TextField("計劃名稱", text: $planName)
                    
                    Picker("計劃類型", selection: $planType) {
                        ForEach(WorkoutPlanType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    
                    DatePicker("訓練時間", selection: $scheduledTime, displayedComponents: .hourAndMinute)
                    
                    Stepper("預估時長: \(estimatedDuration) 分鐘", value: $estimatedDuration, in: 15...180, step: 15)
                }
                
                Section("訓練內容") {
                    Button {
                        showTemplatePicker = true
                    } label: {
                        HStack {
                            Text("選擇模板")
                            Spacer()
                            if let template = selectedTemplate {
                                Text(template.name)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("未選擇")
                                    .foregroundColor(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("新增訓練計劃")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("儲存") {
                        savePlan()
                    }
                    .disabled(planName.isEmpty)
                }
            }
            .sheet(isPresented: $showTemplatePicker) {
                TemplatePickerSheet { template in
                    selectedTemplate = template
                }
            }
        }
    }
    
    private func savePlan() {
        // 計算預估容量
        let estimatedVolume = selectedTemplate?.exercises.reduce(0) { total, exercise in
            let sets = exercise.suggestedSets ?? 3
            let reps = exercise.suggestedReps ?? 10
            let weight = 50.0 // 預設重量，實際應該從用戶歷史記錄中獲取
            return total + (Double(sets * reps) * weight)
        } ?? 0
        
        let plan = WorkoutPlan(
            name: planName,
            type: planType,
            scheduledDate: scheduledTime,
            estimatedDuration: estimatedDuration,
            exercises: selectedTemplate?.exercises.map { templateExercise in
                PlannedExercise(
                    exerciseId: templateExercise.exercise.id,
                    exerciseName: templateExercise.exercise.name,
                    plannedSets: (0..<(templateExercise.suggestedSets ?? 3)).map { setIndex in
                        PlannedSet(
                            weight: 50.0, // 預設重量
                            reps: templateExercise.suggestedReps ?? 10,
                            restSeconds: 90, // 預設休息時間
                            note: nil
                        )
                    },
                    note: nil
                )
            } ?? [],
            estimatedVolume: estimatedVolume,
            note: nil
        )
        
        onSave(plan)
        dismiss()
    }
}

// MARK: - Workout Plan Detail View

struct WorkoutPlanDetailView: View {
    let plan: WorkoutPlan
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 計劃標題
                    VStack(alignment: .leading, spacing: 8) {
                        Text(plan.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        HStack {
                            Text(plan.type.displayName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text(plan.scheduledDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // 計劃統計
                    HStack(spacing: 20) {
                        StatCard(title: "預估時長", value: "\(plan.estimatedDuration) 分鐘", icon: "clock", color: .blue)
                        StatCard(title: "動作數量", value: "\(plan.exercises.count) 個", icon: "figure.strengthtraining.traditional", color: .green)
                        StatCard(title: "預估容量", value: "\(Int(plan.estimatedVolume)) kg", icon: "chart.bar", color: .orange)
                    }
                    
                    // 動作列表
                    if !plan.exercises.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("訓練動作")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            ForEach(plan.exercises) { exercise in
                                ExercisePlanCard(exercise: exercise)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("計劃詳情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// StatItem 定義已移至 Views/Components/StatCardView.swift

struct ExercisePlanCard: View {
    let exercise: PlannedExercise
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(exercise.exerciseName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(exercise.plannedSets.count) 組")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if !exercise.plannedSets.isEmpty {
                HStack {
                    ForEach(exercise.plannedSets.prefix(3)) { set in
                        Text("\(Int(set.weight))kg × \(set.reps)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    if exercise.plannedSets.count > 3 {
                        Text("+\(exercise.plannedSets.count - 3)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

// MARK: - Data Models

struct WorkoutPlan: Identifiable, Codable {
    let id = UUID()
    let name: String
    let type: WorkoutPlanType
    let scheduledDate: Date
    let estimatedDuration: Int
    let exercises: [PlannedExercise]
    let estimatedVolume: Double
    let note: String?
    let createdAt: Date
    let updatedAt: Date
    
    init(name: String, type: WorkoutPlanType, scheduledDate: Date, estimatedDuration: Int, exercises: [PlannedExercise], estimatedVolume: Double, note: String?) {
        self.name = name
        self.type = type
        self.scheduledDate = scheduledDate
        self.estimatedDuration = estimatedDuration
        self.exercises = exercises
        self.estimatedVolume = estimatedVolume
        self.note = note
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

struct PlannedExercise: Identifiable, Codable {
    let id = UUID()
    let exerciseId: UUID
    let exerciseName: String
    let plannedSets: [PlannedSet]
    let note: String?
    
    init(exerciseId: UUID, exerciseName: String, plannedSets: [PlannedSet], note: String? = nil) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.plannedSets = plannedSets
        self.note = note
    }
}

struct PlannedSet: Identifiable, Codable {
    let id = UUID()
    let weight: Double
    let reps: Int
    let restSeconds: Int?
    let note: String?
    
    init(weight: Double, reps: Int, restSeconds: Int? = nil, note: String? = nil) {
        self.weight = weight
        self.reps = reps
        self.restSeconds = restSeconds
        self.note = note
    }
}

enum WorkoutPlanType: String, Codable, CaseIterable {
    case strength = "strength"
    case cardio = "cardio"
    case flexibility = "flexibility"
    case mixed = "mixed"
    
    var displayName: String {
        switch self {
        case .strength: return "肌力訓練"
        case .cardio: return "有氧運動"
        case .flexibility: return "柔軟度"
        case .mixed: return "混合訓練"
        }
    }
    
    var color: Color {
        switch self {
        case .strength: return .blue
        case .cardio: return .red
        case .flexibility: return .green
        case .mixed: return .purple
        }
    }
}

// MARK: - View Model

@MainActor
class CalendarPlanningViewModel: ObservableObject {
    @Published var plans: [WorkoutPlan] = []
    @Published var isLoading = false
    
    func loadPlans() {
        isLoading = true
        // TODO: 從資料庫載入計劃
        // 目前使用模擬資料
        plans = [
            WorkoutPlan(
                name: "胸肌訓練",
                type: .strength,
                scheduledDate: Date(),
                estimatedDuration: 60,
                exercises: [],
                estimatedVolume: 1500,
                note: nil
            )
        ]
        isLoading = false
    }
    
    func addPlan(_ plan: WorkoutPlan) {
        plans.append(plan)
        // TODO: 儲存到資料庫
    }
    
    func deletePlan(_ plan: WorkoutPlan) {
        plans.removeAll { $0.id == plan.id }
        // TODO: 從資料庫刪除
    }
}

#Preview {
    CalendarPlanningView()
}
