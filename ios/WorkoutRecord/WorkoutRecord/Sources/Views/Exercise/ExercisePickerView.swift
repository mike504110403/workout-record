import SwiftUI

struct ExercisePickerView: View {
    @StateObject private var viewModel = ExercisePickerViewModel()
    @StateObject private var customExerciseVM = CustomExerciseViewModel()
    @Environment(\.dismiss) var dismiss
    
    let onSelectExercise: (Exercise) -> Void
    
    @State private var searchText = ""
    @State private var selectedCategory: ExerciseCategory?
    @State private var showQuickAdd = false
    @State private var autoRefreshTimer: Timer?
    
    // 即時搜尋結果
    private var searchResults: [Exercise] {
        if searchText.isEmpty {
            return []
        }
        return viewModel.searchExercises(query: searchText)
    }
    
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
            .onAppear {
                print("📱 ExercisePickerView appeared")
                print("   - allExercises count: \(viewModel.allExercises.count)")
                print("   - categories count: \(viewModel.categories.count)")
                print("   - isLoading: \(viewModel.isLoading)")
                print("   - searchText: '\(searchText)'")
                print("   - selectedCategory: \(selectedCategory?.name ?? "nil")")
                
                // 檢查數據初始化狀態
                let isInitialized = UserDefaults.standard.bool(forKey: "DefaultDataInitialized")
                print("   - DefaultDataInitialized: \(isInitialized)")
                
                // 總是重新載入以確保數據最新
                viewModel.refresh()
                
                // ✅ 如果數據為空且還沒初始化完成，每秒自動重試
                startAutoRefreshIfNeeded()
            }
            .onDisappear {
                stopAutoRefresh()
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
                // 添加調試信息
                let _ = print("🔍 exerciseList 渲染狀態:")
                let _ = print("   - isLoading: \(viewModel.isLoading)")
                let _ = print("   - errorMessage: \(viewModel.errorMessage ?? "nil")")
                let _ = print("   - allExercises.isEmpty: \(viewModel.allExercises.isEmpty)")
                let _ = print("   - searchText.isEmpty: \(searchText.isEmpty)")
                
                if viewModel.isLoading {
                    // 載入中
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("載入動作中...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else if let errorMessage = viewModel.errorMessage {
                    // 錯誤狀態
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        Text("載入失敗")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("重試") {
                            viewModel.refresh()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .padding(.top, 40)
                } else if viewModel.allExercises.isEmpty {
                    // 空狀態
                    VStack(spacing: 16) {
                        Image(systemName: "dumbbell")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("暫無動作")
                            .font(.headline)
                        Text("系統正在初始化動作庫...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("重新載入") {
                            viewModel.refresh()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .padding(.top, 40)
                } else if searchText.isEmpty {
                    // 添加調試：顯示分類數量
                    let _ = print("📂 準備顯示分類列表，categories count: \(viewModel.categories.count)")
                    
                    // Show by category
                    if let selectedCategory = selectedCategory {
                        let _ = print("   選中分類: \(selectedCategory.name)")
                        exerciseSection(for: selectedCategory)
                    } else {
                        let _ = print("   顯示所有分類")
                        
                        // ⚠️ 調試：如果 categories 為空，顯示提示
                        if viewModel.categories.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "folder.badge.questionmark")
                                    .font(.system(size: 48))
                                    .foregroundColor(.orange)
                                Text("分類載入異常")
                                    .font(.headline)
                                Text("有 \(viewModel.allExercises.count) 個動作，但沒有分類")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Button("重新載入") {
                                    viewModel.refresh()
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding()
                            .padding(.top, 40)
                        } else {
                            // Show all categories
                            ForEach(viewModel.categories) { category in
                                exerciseSection(for: category)
                            }
                        }
                    }
                } else {
                    // 即時搜尋結果（每打一個字都更新）
                    if searchResults.isEmpty {
                        emptySearchResults
                    } else {
                        // 顯示搜尋結果數量
                        HStack {
                            Text("找到 \(searchResults.count) 個動作")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground))
                        
                        ForEach(searchResults) { exercise in
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
        let _ = print("📋 Section \(category.name): \(exercises.count) 個動作")
        
        return Group {
            if !exercises.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    // Section header
                    if selectedCategory == nil {
                        HStack {
                            Text(category.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(exercises.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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
    
    // MARK: - Auto Refresh
    
    /// 如果數據為空且尚未初始化完成，啟動自動刷新
    private func startAutoRefreshIfNeeded() {
        // 如果已經有數據，不需要自動刷新
        if !viewModel.allExercises.isEmpty {
            return
        }
        
        // 如果已經初始化完成但還是空的，也不需要自動刷新
        let isInitialized = UserDefaults.standard.bool(forKey: "DefaultDataInitialized")
        if isInitialized {
            return
        }
        
        print("⏰ 啟動自動刷新（等待數據初始化）")
        
        // 每秒自動重試一次，最多重試 10 次
        var retryCount = 0
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            retryCount += 1
            print("🔄 自動刷新 (第 \(retryCount) 次)")
            
            viewModel.refresh()
            
            // 如果載入成功或超過最大重試次數，停止定時器
            let isNowInitialized = UserDefaults.standard.bool(forKey: "DefaultDataInitialized")
            if !viewModel.allExercises.isEmpty || isNowInitialized || retryCount >= 10 {
                print("✅ 停止自動刷新")
                timer.invalidate()
                autoRefreshTimer = nil
            }
        }
    }
    
    /// 停止自動刷新
    private func stopAutoRefresh() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
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
                    HStack(spacing: 6) {
                        Text(exercise.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        // 自定義動作標記
                        if !exercise.isSystem {
                            Text("自訂")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .cornerRadius(4)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        if let nameEn = exercise.nameEn {
                            Text(nameEn)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // 優先顯示新的詳細肌群
                        if !exercise.targetMuscles.isEmpty {
                            Text("・")
                                .foregroundColor(.secondary)
                            
                            Text(exercise.targetMuscles.prefix(2).map { $0.displayName }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if !exercise.muscleGroups.isEmpty {
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

