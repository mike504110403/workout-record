import SwiftUI

struct ExerciseManagementView: View {
    @StateObject private var exerciseService = ExerciseService()
    @State private var searchText = ""
    @State private var selectedCategory: DetailedMuscleGroup? = nil
    @State private var showingAddExercise = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜尋欄
                SearchBar(text: $searchText)
                    .padding()
                
                // 分類篩選
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        FilterChipView(
                            title: "全部",
                            isSelected: selectedCategory == nil
                        ) {
                            selectedCategory = nil
                        }
                        
                        ForEach(DetailedMuscleGroup.allCases, id: \.self) { category in
                            FilterChipView(
                                title: category.displayName,
                                isSelected: selectedCategory == category
                            ) {
                                selectedCategory = category
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom)
                
                // 動作列表
                if filteredExercises.isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "找不到動作",
                        message: searchText.isEmpty ? "沒有符合條件的動作" : "請嘗試其他搜尋關鍵字"
                    )
                    .padding()
                } else {
                    List {
                        ForEach(filteredExercises) { exercise in
                            ExerciseRow(exercise: exercise)
                        }
                        .onDelete(perform: deleteExercises)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("動作庫")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddExercise = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddExercise) {
                CustomExerciseFormView(
                    viewModel: CustomExerciseViewModel(),
                    mode: .create
                )
            }
            .onAppear {
                // exerciseService.loadExercises() // 移除，因為方法不存在
            }
        }
    }
    
    private var filteredExercises: [Exercise] {
        var exercises: [Exercise] = [] // 暫時設為空陣列
        
        // 分類篩選
        if let category = selectedCategory {
            exercises = exercises.filter { $0.targetMuscles.contains(category) }
        }
        
        // 搜尋篩選
        if !searchText.isEmpty {
            exercises = exercises.filter { exercise in
                exercise.name.localizedCaseInsensitiveContains(searchText) ||
                exercise.targetMuscles.contains { $0.displayName.localizedCaseInsensitiveContains(searchText) }
            }
        }
        
        return exercises
    }
    
    private func deleteExercises(offsets: IndexSet) {
        for index in offsets {
            let exercise = filteredExercises[index]
            // exerciseService.deleteExercise(exercise) // 移除，因為方法不存在
        }
    }
}

struct ExerciseRow: View {
    let exercise: Exercise
    @StateObject private var exerciseService = ExerciseService()
    
    var body: some View {
        HStack(spacing: 12) {
            // 動作圖示
            Image(systemName: "dumbbell.fill") // 使用預設圖示
                .font(.title2)
                .foregroundColor(.blue) // 使用預設顏色
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.headline)
                
                Text(exercise.targetMuscles.first?.displayName ?? "未分類")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 使用次數
            if false { // 暫時移除 usageCount 檢查
                VStack(alignment: .trailing, spacing: 2) {
                    Text("0") // 暫時設為 0
                        .font(.headline)
                        .foregroundColor(.blue)
                    
                    Text("次使用")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("搜尋動作", text: $text)
                .textFieldStyle(.plain)
            
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

#Preview {
    ExerciseManagementView()
}
