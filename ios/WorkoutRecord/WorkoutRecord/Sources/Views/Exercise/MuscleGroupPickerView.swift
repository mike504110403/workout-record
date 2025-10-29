import SwiftUI

struct MuscleGroupPickerView: View {
    let selectedCategory: ExerciseCategory?
    let primaryMuscleGroup: Exercise.PrimaryMuscleGroup?
    @Binding var selectedMuscles: Set<DetailedMuscleGroup>
    @Environment(\.dismiss) private var dismiss
    
    // 根據分類或主要肌群過濾可用的肌群
    private var availableMuscles: [DetailedMuscleGroup] {
        if let primaryGroup = primaryMuscleGroup {
            return DetailedMuscleGroup.muscles(for: primaryGroup)
        } else if let category = selectedCategory {
            return DetailedMuscleGroup.muscles(forCategoryName: category.name)
        } else {
            return DetailedMuscleGroup.allCases
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if primaryMuscleGroup != nil || selectedCategory != nil {
                    Section {
                        Text("根據分類「\(selectedCategory?.name ?? "")」自動篩選肌群")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("選擇目標肌群（可多選）") {
                    ForEach(availableMuscles) { muscle in
                        MuscleGroupRow(
                            muscle: muscle,
                            isSelected: selectedMuscles.contains(muscle)
                        ) {
                            toggleMuscle(muscle)
                        }
                    }
                }
                
                if !selectedMuscles.isEmpty {
                    Section("已選擇 \(selectedMuscles.count) 個肌群") {
                        Text(selectedMuscles.map { $0.displayName }.sorted().joined(separator: "、"))
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("選擇目標肌群")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func toggleMuscle(_ muscle: DetailedMuscleGroup) {
        if selectedMuscles.contains(muscle) {
            selectedMuscles.remove(muscle)
        } else {
            selectedMuscles.insert(muscle)
        }
    }
}

struct MuscleGroupRow: View {
    let muscle: DetailedMuscleGroup
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(muscle.displayName)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Text(muscle.displayNameEn)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(muscle.color)
                        .font(.title3)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MuscleGroupPickerView(
        selectedCategory: ExerciseCategory(name: "胸部", nameEn: "Chest"),
        primaryMuscleGroup: .chest,
        selectedMuscles: .constant([.upperChest, .midChest])
    )
}

