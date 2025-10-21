import SwiftUI

struct CustomExerciseListView: View {
    @StateObject private var viewModel = CustomExerciseViewModel()
    @State private var showingAddSheet = false
    @State private var editingExercise: Exercise?
    
    var body: some View {
        List {
            if viewModel.customExercises.isEmpty {
                emptyState
            } else {
                ForEach(viewModel.customExercises) { exercise in
                    CustomExerciseRow(exercise: exercise) {
                        editingExercise = exercise
                    }
                }
                .onDelete(perform: viewModel.deleteExercises)
            }
        }
        .navigationTitle("自定義動作")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            CustomExerciseFormView(viewModel: viewModel, mode: .create)
        }
        .sheet(item: $editingExercise) { exercise in
            CustomExerciseFormView(viewModel: viewModel, mode: .edit(exercise))
        }
        .onAppear {
            viewModel.loadExercises()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("還沒有自定義動作")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("點擊右上角的 + 來創建你的第一個自定義動作")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

struct CustomExerciseRow: View {
    let exercise: Exercise
    let onEdit: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 圖標
            Circle()
                .fill(muscleGroupColor.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: exerciseIcon)
                        .foregroundColor(muscleGroupColor)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.body)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    if let muscleGroup = exercise.primaryMuscleGroup {
                        TagView(text: muscleGroup.displayName, color: muscleGroupColor)
                    }
                    
                    if let pattern = exercise.movementPattern {
                        TagView(text: pattern.displayName, color: .blue)
                    }
                    
                    TagView(text: exercise.type.displayName, color: .gray)
                }
            }
            
            Spacer()
            
            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
    
    private var muscleGroupColor: Color {
        guard let group = exercise.primaryMuscleGroup else { return .gray }
        switch group {
        case .chest: return .red
        case .back: return .blue
        case .legs: return .green
        case .shoulders: return .orange
        case .arms: return .purple
        case .core: return .yellow
        case .glutes: return .pink
        case .fullBody: return .gray
        }
    }
    
    private var exerciseIcon: String {
        switch exercise.type {
        case .freeWeight: return "dumbbell.fill"
        case .machine: return "gearshape.fill"
        case .bodyweight: return "figure.walk"
        }
    }
}

struct TagView: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

#Preview {
    NavigationStack {
        CustomExerciseListView()
    }
}

