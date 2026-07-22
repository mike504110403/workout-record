import SwiftUI

struct WorkoutView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @StateObject private var globalSettings = GlobalSettingsManager.shared
    @StateObject private var restTimerManager = RestTimerManager()
    @State private var showExercisePicker = false
    @State private var showAddSetSheet = false
    @State private var showTemplatePicker = false
    @State private var showRestCompleteAlert = false
    @State private var selectedExercise: WorkoutExerciseViewModel?
    
    // 傳遞 restTimerManager 給子視圖使用
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Rest Timer Header (只在計時時顯示)
                if restTimerManager.isRunning {
                    RestTimerHeaderView(timerManager: restTimerManager)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                if viewModel.isWorkoutInProgress {
                    // Show workout in progress view
                    WorkoutInProgressView(
                        viewModel: viewModel,
                        globalSettings: globalSettings,
                        restTimerManager: restTimerManager,
                        showExercisePicker: $showExercisePicker,
                        showAddSetSheet: $showAddSetSheet,
                        selectedExercise: $selectedExercise
                    )
                } else {
                    // Show start workout view
                    StartWorkoutView(
                        viewModel: viewModel,
                        showTemplatePicker: $showTemplatePicker
                    )
                }
            }
            .navigationTitle("訓練記錄")
            .sheet(isPresented: $showExercisePicker) {
                ExercisePickerView { exercise in
                    viewModel.addExercise(exercise)
                }
            }
            .sheet(isPresented: $showAddSetSheet) {
                if let exercise = selectedExercise {
                    let lastSet = exercise.sets.last
                    AddSetSheet(
                        exerciseName: exercise.exerciseName,
                        setNumber: exercise.sets.count + 1,
                        previousWeight: lastSet?.weight,
                        previousReps: lastSet?.reps,
                        onSave: { weight, reps, rpe, restSeconds in
                            viewModel.addSet(to: exercise, weight: weight, reps: reps, rpe: rpe)
                            selectedExercise = nil
                            
                            // Start rest timer with user-selected duration
                            restTimerManager.setup(seconds: restSeconds, exerciseName: exercise.exerciseName)
                            restTimerManager.start()
                        }
                    )
                }
            }
            .sheet(isPresented: $showTemplatePicker) {
                TemplatePickerSheet { template in
                    viewModel.startWorkoutFromTemplate(template)
                }
            }
            .sheet(isPresented: $viewModel.showWorkoutReport) {
                if let workout = viewModel.completedWorkout {
                    WorkoutSummaryReportView(workout: workout)
                }
            }
            .alert("休息時間結束", isPresented: $showRestCompleteAlert) {
                Button("知道了", role: .cancel) { }
            } message: {
                if let exerciseName = restTimerManager.exerciseName {
                    Text("準備好進行下一組 \(exerciseName) 了嗎？")
                } else {
                    Text("準備好進行下一組了嗎？")
                }
            }
            .onChange(of: restTimerManager.remainingSeconds) { oldValue, newValue in
                if newValue == 0 && oldValue > 0 {
                    // 時間結束，彈出提示
                    showRestCompleteAlert = true
                    // 播放提示音
                    restTimerManager.playCompletionSound()
                }
            }
        }
    }
}

struct StartWorkoutView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Binding var showTemplatePicker: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("開始新的訓練")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("選擇訓練模板或自由訓練")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                Button {
                    viewModel.startWorkout()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("開始自由訓練")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                
                Button {
                    showTemplatePicker = true
                } label: {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("從模板開始")
                    }
                    .font(.headline)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 40)
        }
    }
}

struct WorkoutInProgressView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @ObservedObject var globalSettings: GlobalSettingsManager
    @ObservedObject var restTimerManager: RestTimerManager
    @Binding var showExercisePicker: Bool
    @Binding var showAddSetSheet: Bool
    @Binding var selectedExercise: WorkoutExerciseViewModel?
    @State private var editingExercise: WorkoutExerciseViewModel?
    @State private var showEditExerciseSheet = false
    
    // 檢查是否有未完成的動作
    private var hasIncompleteExercises: Bool {
        viewModel.currentWorkoutExercises.contains { !$0.isCompleted }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Workout header with stats
            workoutHeader
            
            // Exercises list
            List {
                // Add exercise button - only show when no incomplete exercises
                if !hasIncompleteExercises {
                    Button {
                        showExercisePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("新增動作")
                        }
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                
                // Current active exercise (larger)
                if let activeExercise = viewModel.currentWorkoutExercises.first(where: { !$0.isCompleted }) {
                    WorkoutExerciseCard(
                        exercise: activeExercise,
                        isActive: true,
                        onAddSet: {
                            selectedExercise = activeExercise
                            showAddSetSheet = true
                        },
                        onDeleteSet: { set in viewModel.deleteSet(set, from: activeExercise) },
                        onUpdateSet: { set, weight, reps, rpe in
                            viewModel.updateSet(set, from: activeExercise, weight: weight, reps: reps, rpe: rpe)
                        },
                        onCompleteExercise: {
                            // 完成動作時停止休息計時器
                            restTimerManager.stop()
                            viewModel.completeExercise(activeExercise)
                        },
                        onDeleteExercise: {
                            viewModel.deleteExercise(activeExercise)
                        }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            restTimerManager.stop() // 停止計時器
                            viewModel.deleteExercise(activeExercise)
                        } label: {
                            Label("刪除", systemImage: "trash")
                        }
                    }
                }
                
                // Completed exercises (collapsed, clickable to expand)
                ForEach(viewModel.currentWorkoutExercises.filter { $0.isCompleted }) { exercise in
                    CompletedExerciseRow(
                        exercise: exercise,
                        onTap: {
                            // Toggle expansion state
                            viewModel.toggleExerciseExpansion(exercise)
                        },
                        onDeleteExercise: {
                            viewModel.deleteExercise(exercise)
                        },
                        onEditExercise: {
                            editingExercise = exercise
                            showEditExerciseSheet = true
                        },
                        onDeleteSet: { set in viewModel.deleteSet(set, from: exercise) },
                        onUpdateSet: { set, weight, reps, rpe in
                            viewModel.updateSet(set, from: exercise, weight: weight, reps: reps, rpe: rpe)
                        }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            viewModel.deleteExercise(exercise)
                        } label: {
                            Label("刪除", systemImage: "trash")
                        }
                        
                        Button {
                            editingExercise = exercise
                            showEditExerciseSheet = true
                        } label: {
                            Label("編輯", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            
            // Bottom action buttons
            HStack(spacing: 12) {
                Button {
                    viewModel.cancelWorkout()
                } label: {
                    Text("放棄")
                        .font(.headline)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                }
                
                Button {
                    viewModel.completeWorkout()
                } label: {
                    Text("完成訓練")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.canCompleteWorkout ? Color.green : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(!viewModel.canCompleteWorkout)
                .opacity(viewModel.canCompleteWorkout ? 1.0 : 0.6)
            }
            .padding()
            .background(Color(.systemBackground))
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: -2)
        }
        .sheet(isPresented: $showEditExerciseSheet) {
            if let exercise = editingExercise {
                EditExerciseSheet(exercise: exercise) { editedSets in
                    viewModel.updateExerciseSets(exercise, with: editedSets)
                }
            }
        }
    }
    
    private var workoutHeader: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("訓練時長")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(viewModel.workoutDuration)
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("總容量")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(globalSettings.formatWeight(viewModel.totalVolume))
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("總組數")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(viewModel.totalSets)")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }
}

struct WorkoutExerciseCard: View {
    let exercise: WorkoutExerciseViewModel
    let isActive: Bool
    let onAddSet: () -> Void
    let onDeleteSet: (WorkoutSetViewModel) -> Void
    let onUpdateSet: (WorkoutSetViewModel, Double, Int, Double?) -> Void
    let onCompleteExercise: () -> Void  // 新增：完成動作回調
    let onDeleteExercise: () -> Void  // 新增：刪除動作回調
    @StateObject private var globalSettings = GlobalSettingsManager.shared
    @State private var showNoSetsAlert = false
    @State private var editingSet: WorkoutSetViewModel?
    
    private var hasAtLeastOneSet: Bool {
        !exercise.sets.isEmpty
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(exercise.exerciseName)
                    .font(isActive ? .title2 : .headline)
                    .fontWeight(isActive ? .bold : .medium)
                
                Spacer()
                
                Text(globalSettings.formatWeight(exercise.totalVolume))
                    .font(isActive ? .headline : .subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }
            
            // Sets list
            VStack(spacing: 8) {
                // Header
                HStack {
                    Text("組")
                        .frame(width: 30)
                    Text("重量")
                        .frame(maxWidth: .infinity)
                    Text("次數")
                        .frame(maxWidth: .infinity)
                    Text("容量")
                        .frame(maxWidth: .infinity)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                ForEach(exercise.sets) { set in
                    SetRow(
                        set: set,
                        globalSettings: globalSettings,
                        onEdit: { editingSet = set },
                        onDelete: { onDeleteSet(set) }
                    )
                }
            }
            
            // Action buttons
            HStack(spacing: 12) {
                if !exercise.isCompleted {
                    Button {
                        onAddSet()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("新增組數")
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        if hasAtLeastOneSet {
                            onCompleteExercise()
                        } else {
                            showNoSetsAlert = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle")
                            Text("完成動作")
                        }
                        .font(.subheadline)
                        .foregroundColor(hasAtLeastOneSet ? .green : .gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background((hasAtLeastOneSet ? Color.green : Color.gray).opacity(0.05))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .opacity(hasAtLeastOneSet ? 1.0 : 0.5)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("已完成")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
        .alert("無法完成動作", isPresented: $showNoSetsAlert) {
            Button("確定", role: .cancel) { }
        } message: {
            Text("請至少記錄一組訓練後再完成動作")
        }
        .sheet(item: $editingSet) { set in
            EditSetSheet(set: set) { weight, reps, rpe in
                onUpdateSet(set, weight, reps, rpe)
            }
        }
    }
}

// MARK: - Template Picker Sheet
struct TemplatePickerSheet: View {
    @StateObject private var viewModel = WorkoutTemplateViewModel()
    @Environment(\.dismiss) var dismiss
    let onSelect: (TemplateInfo) -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.templates.isEmpty {
                    emptyState
                } else {
                    templateList
                }
            }
            .navigationTitle("選擇訓練模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text("尚無可用的模板")
                .font(.headline)
            
            Text("前往設定建立訓練模板")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    private var templateList: some View {
        LazyVStack(spacing: 16) {
            // System templates
            if !viewModel.systemTemplates.isEmpty {
                Section {
                    ForEach(viewModel.systemTemplates) { template in
                        TemplatePickerCard(template: template) {
                            onSelect(template)
                            dismiss()
                        }
                    }
                } header: {
                    HStack {
                        Text("系統模板")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal)
                }
            }
            
            // User templates
            if !viewModel.userTemplates.isEmpty {
                Section {
                    ForEach(viewModel.userTemplates) { template in
                        TemplatePickerCard(template: template) {
                            onSelect(template)
                            dismiss()
                        }
                    }
                } header: {
                    HStack {
                        Text("我的模板")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top)
                }
            }
        }
        .padding(.vertical)
    }
}

struct TemplatePickerCard: View {
    let template: TemplateInfo
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        if let description = template.description {
                            Text(description)
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
                
                // Exercise preview
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "list.bullet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(template.exercises.count) 個動作")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    ForEach(template.exercises.prefix(3), id: \.name) { exercise in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 4, height: 4)
                            
                            Text(exercise.name)
                                .font(.caption)
                                .foregroundColor(.primary)
                            
                            if let sets = exercise.suggestedSets, let reps = exercise.suggestedReps {
                                Text("\(sets) 組 × \(reps) 次")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if template.exercises.count > 3 {
                        Text("還有 \(template.exercises.count - 3) 個...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Set Row (with swipe gesture for edit/delete)
struct SetRow: View {
    let set: WorkoutSetViewModel
    let globalSettings: GlobalSettingsManager
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var offset: CGFloat = 0
    @State private var isSwipedOpen = false
    @GestureState private var dragState: CGFloat = 0
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // 背景的編輯/刪除按鈕
            HStack(spacing: 0) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        offset = 0
                        isSwipedOpen = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onEdit()
                    }
                } label: {
                    Image(systemName: "pencil")
                        .foregroundColor(.white)
                        .frame(width: 70, height: 44)
                        .background(Color.blue)
                }
                
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        offset = 0
                        isSwipedOpen = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.white)
                        .frame(width: 70, height: 44)
                        .background(Color.red)
                }
            }
            
            // 前景的組數內容
            HStack {
                Text("\(set.setNumber)")
                    .frame(width: 30)
                
                Text(globalSettings.formatWeight(set.weight))
                    .frame(maxWidth: .infinity)
                
                Text("\(set.reps)")
                    .frame(maxWidth: .infinity)
                
                Text(globalSettings.formatWeight(set.volume))
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.blue)
            }
            .font(.subheadline)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .offset(x: offset + dragState)
            .highPriorityGesture(
                DragGesture(minimumDistance: 15)
                    .updating($dragState) { value, state, _ in
                        if value.translation.width < 0 {
                            // 左滑
                            state = max(value.translation.width, -140 - offset)
                        } else if isSwipedOpen {
                            // 右滑關閉
                            state = value.translation.width
                        }
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if value.translation.width < -50 && !isSwipedOpen {
                                // 打開
                                offset = -140
                                isSwipedOpen = true
                            } else if value.translation.width > 50 && isSwipedOpen {
                                // 關閉
                                offset = 0
                                isSwipedOpen = false
                            } else if isSwipedOpen {
                                // 維持打開
                                offset = -140
                            } else {
                                // 維持關閉
                                offset = 0
                            }
                        }
                    }
            )
        }
        .clipped()
    }
}

struct CompletedExerciseRow: View {
    let exercise: WorkoutExerciseViewModel
    let onTap: () -> Void
    let onDeleteExercise: () -> Void
    let onEditExercise: () -> Void
    let onDeleteSet: (WorkoutSetViewModel) -> Void
    let onUpdateSet: (WorkoutSetViewModel, Double, Int, Double?) -> Void
    @StateObject private var globalSettings = GlobalSettingsManager.shared
    @State private var isExpanded = false
    @State private var editingSet: WorkoutSetViewModel?
    
    var body: some View {
        VStack(spacing: 0) {
            // Collapsed row
            Button(action: {
                isExpanded.toggle()
                onTap()
            }) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                    
                    Text(exercise.exerciseName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(globalSettings.formatWeight(exercise.totalVolume))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded content
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(exercise.sets) { set in
                        SetRow(
                            set: set,
                            globalSettings: globalSettings,
                            onEdit: { editingSet = set },
                            onDelete: { onDeleteSet(set) }
                        )
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(Color(.quaternarySystemFill))
                .cornerRadius(8)
            }
        }
        .padding(.horizontal)
        .sheet(item: $editingSet) { set in
            EditSetSheet(set: set) { weight, reps, rpe in
                onUpdateSet(set, weight, reps, rpe)
            }
        }
    }
}

#Preview {
    @MainActor
    struct PreviewWrapper: View {
        @StateObject private var viewModel = WorkoutViewModel()
        
        var body: some View {
            WorkoutView(viewModel: viewModel)
        }
    }
    
    return PreviewWrapper()
}

