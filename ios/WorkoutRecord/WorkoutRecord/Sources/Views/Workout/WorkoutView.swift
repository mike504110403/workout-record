import SwiftUI

struct WorkoutView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @State private var showExercisePicker = false
    @State private var showAddSetSheet = false
    @State private var showRestTimer = false
    @State private var showTemplatePicker = false
    @State private var selectedExercise: WorkoutExerciseViewModel?
    @State private var restTimerExerciseName = ""
    @State private var restTimerSeconds = 90
    
    var body: some View {
        NavigationStack {
            VStack {
                if viewModel.isWorkoutInProgress {
                    // Show workout in progress view
                    WorkoutInProgressView(
                        viewModel: viewModel,
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
                    AddSetSheet(
                        exerciseName: exercise.exerciseName,
                        setNumber: exercise.sets.count + 1,
                        onSave: { weight, reps, rpe in
                            viewModel.addSet(to: exercise, weight: weight, reps: reps, rpe: rpe)
                            selectedExercise = nil
                            
                            // Show rest timer
                            restTimerExerciseName = exercise.exerciseName
                            restTimerSeconds = 90 // TODO: Get from settings or last set
                            showRestTimer = true
                        }
                    )
                }
            }
            .fullScreenCover(isPresented: $showRestTimer) {
                RestTimerView(
                    seconds: restTimerSeconds,
                    exerciseName: restTimerExerciseName
                )
            }
            .sheet(isPresented: $showTemplatePicker) {
                TemplatePickerSheet { template in
                    viewModel.startWorkoutFromTemplate(template)
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
    @Binding var showExercisePicker: Bool
    @Binding var showAddSetSheet: Bool
    @Binding var selectedExercise: WorkoutExerciseViewModel?
    
    var body: some View {
        VStack(spacing: 0) {
            // Workout header with stats
            workoutHeader
            
            // Exercises list
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(viewModel.currentWorkoutExercises) { exercise in
                    WorkoutExerciseCard(
                        exercise: exercise,
                        onAddSet: {
                            selectedExercise = exercise
                            showAddSetSheet = true
                        },
                        onDeleteSet: { set in viewModel.deleteSet(set, from: exercise) }
                    )
                    }
                    
                    // Add exercise button
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
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            
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
                        .background(Color.green)
                        .cornerRadius(12)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: -2)
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
                    Text(String(format: "%.0f kg", viewModel.totalVolume))
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
    let onAddSet: () -> Void
    let onDeleteSet: (WorkoutSetViewModel) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(exercise.exerciseName)
                    .font(.headline)
                
                Spacer()
                
                Text(String(format: "%.0f kg", exercise.totalVolume))
                    .font(.subheadline)
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
                    Text("")
                        .frame(width: 30)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                ForEach(exercise.sets) { set in
                    HStack {
                        Text("\(set.setNumber)")
                            .frame(width: 30)
                        
                        Text(String(format: "%.0f", set.weight))
                            .frame(maxWidth: .infinity)
                        
                        Text("\(set.reps)")
                            .frame(maxWidth: .infinity)
                        
                        Text(String(format: "%.0f", set.volume))
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.blue)
                        
                        Button {
                            onDeleteSet(set)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        .frame(width: 30)
                    }
                    .font(.subheadline)
                }
            }
            
            // Add set button
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
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
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

