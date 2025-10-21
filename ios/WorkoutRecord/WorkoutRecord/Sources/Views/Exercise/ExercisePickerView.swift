import SwiftUI

struct ExercisePickerView: View {
    @StateObject private var viewModel = ExercisePickerViewModel()
    @StateObject private var customExerciseVM = CustomExerciseViewModel()
    @Environment(\.dismiss) var dismiss
    
    let onSelectExercise: (Exercise) -> Void
    
    @State private var searchText = ""
    @State private var selectedCategory: ExerciseCategory?
    @State private var showQuickAdd = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                searchBar
                
                // Category tabs
                if searchText.isEmpty {
                    categoryTabs
                }
                
                // Exercise list
                exerciseList
            }
            .navigationTitle("選擇動作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showQuickAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showQuickAdd) {
                QuickAddExerciseSheet(customExerciseVM: customExerciseVM) { exercise in
                    onSelectExercise(exercise)
                    dismiss()
                }
            }
        }
    }
    
    // MARK: - Search Bar
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("搜尋動作", text: $searchText)
                .textFieldStyle(.plain)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
        .padding()
    }
    
    // MARK: - Category Tabs
    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                CategoryChip(
                    title: "全部",
                    isSelected: selectedCategory == nil
                ) {
                    selectedCategory = nil
                }
                
                ForEach(viewModel.categories) { category in
                    CategoryChip(
                        title: category.name,
                        isSelected: selectedCategory?.id == category.id
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Exercise List
    private var exerciseList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if searchText.isEmpty {
                    // Show by category
                    if let selectedCategory = selectedCategory {
                        exerciseSection(for: selectedCategory)
                    } else {
                        // Show all categories
                        ForEach(viewModel.categories) { category in
                            exerciseSection(for: category)
                        }
                    }
                } else {
                    // Show search results
                    let results = viewModel.searchExercises(query: searchText)
                    if results.isEmpty {
                        emptySearchResults
                    } else {
                        ForEach(results) { exercise in
                            ExerciseRowButton(exercise: exercise) {
                                onSelectExercise(exercise)
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func exerciseSection(for category: ExerciseCategory) -> some View {
        let exercises = viewModel.exercises(for: category)
        
        return Group {
            if !exercises.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    // Section header
                    if selectedCategory == nil {
                        Text(category.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemBackground))
                    }
                    
                    // Exercises
                    ForEach(exercises) { exercise in
                        ExerciseRowButton(exercise: exercise) {
                            onSelectExercise(exercise)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
    
    private var emptySearchResults: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("找不到「\(searchText)」")
                .font(.headline)
            
            Text("試試其他關鍵字或新增自定義動作")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 60)
    }
}

// MARK: - Category Chip
struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(.secondarySystemBackground))
                .cornerRadius(20)
        }
    }
}

// MARK: - Exercise Row Button
struct ExerciseRowButton: View {
    let exercise: Exercise
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Exercise type icon
                Image(systemName: exerciseTypeIcon)
                    .font(.title3)
                    .foregroundColor(.blue)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        if let nameEn = exercise.nameEn {
                            Text(nameEn)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if !exercise.muscleGroups.isEmpty {
                            Text("・")
                                .foregroundColor(.secondary)
                            
                            Text(exercise.muscleGroups.prefix(2).joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Favorite indicator
                if exercise.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        
        Divider()
            .padding(.leading, 56)
    }
    
    private var exerciseTypeIcon: String {
        switch exercise.type {
        case .freeWeight:
            return "dumbbell.fill"
        case .machine:
            return "gearshape.fill"
        case .bodyweight:
            return "figure.walk"
        }
    }
}

#Preview {
    ExercisePickerView { exercise in
        print("Selected: \(exercise.name)")
    }
}

