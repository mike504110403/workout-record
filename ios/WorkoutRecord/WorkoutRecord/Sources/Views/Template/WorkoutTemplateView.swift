import SwiftUI

struct WorkoutTemplateView: View {
    @StateObject private var viewModel = WorkoutTemplateViewModel()
    @State private var showCreateSheet = false
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.templates.isEmpty {
                    emptyState
                } else {
                    templateList
                }
            }
            .navigationTitle("訓練模板")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateTemplateSheet(viewModel: viewModel)
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("尚未建立模板")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("建立訓練模板來快速開始訓練")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                showCreateSheet = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("建立第一個模板")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(12)
            }
        }
        .padding()
    }
    
    private var templateList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // System templates section
                if !viewModel.systemTemplates.isEmpty {
                    Section {
                        ForEach(viewModel.systemTemplates) { template in
                            TemplateCard(
                                template: template,
                                onUse: { viewModel.useTemplate(template) },
                                onEdit: nil,
                                onDelete: nil
                            )
                        }
                    } header: {
                        HStack {
                            Text("系統模板")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top)
                    }
                }
                
                // User templates section
                if !viewModel.userTemplates.isEmpty {
                    Section {
                        ForEach(viewModel.userTemplates) { template in
                            TemplateCard(
                                template: template,
                                onUse: { viewModel.useTemplate(template) },
                                onEdit: { viewModel.editTemplate(template) },
                                onDelete: { viewModel.deleteTemplate(template) }
                            )
                        }
                    } header: {
                        HStack {
                            Text("我的模板")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Template Card
struct TemplateCard: View {
    let template: TemplateInfo
    let onUse: () -> Void
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.headline)
                    
                    if let description = template.description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if !template.isSystem {
                    Menu {
                        if let onEdit = onEdit {
                            Button {
                                onEdit()
                            } label: {
                                Label("編輯", systemImage: "pencil")
                            }
                        }
                        
                        if let onDelete = onDelete {
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Label("刪除", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Divider()
            
            // Exercise list
            VStack(alignment: .leading, spacing: 4) {
                Text("動作")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(template.exercises.prefix(3), id: \.name) { exercise in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                        
                        Text(exercise.name)
                            .font(.subheadline)
                        
                        if let sets = exercise.suggestedSets, let reps = exercise.suggestedReps {
                            Text("\(sets) 組 × \(reps) 次")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if template.exercises.count > 3 {
                    Text("還有 \(template.exercises.count - 3) 個動作...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Use button
            Button {
                onUse()
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("使用此模板")
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.blue)
                .cornerRadius(10)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        .confirmationDialog("確定要刪除此模板？", isPresented: $showDeleteConfirmation) {
            Button("刪除", role: .destructive) {
                onDelete?()
            }
        }
    }
}

// MARK: - Create Template Sheet
struct CreateTemplateSheet: View {
    @ObservedObject var viewModel: WorkoutTemplateViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var name = ""
    @State private var description = ""
    @State private var selectedExercises: [Exercise] = []
    @State private var showExercisePicker = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("模板資訊") {
                    TextField("模板名稱", text: $name)
                    TextField("描述（選填）", text: $description)
                }
                
                Section {
                    Button {
                        showExercisePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("新增動作")
                        }
                        .foregroundColor(.blue)
                    }
                    
                    ForEach(selectedExercises) { exercise in
                        HStack {
                            Text(exercise.name)
                            Spacer()
                            Button {
                                selectedExercises.removeAll { $0.id == exercise.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                } header: {
                    Text("動作列表")
                }
            }
            .navigationTitle("建立模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("儲存") {
                        saveTemplate()
                    }
                    .disabled(name.isEmpty || selectedExercises.isEmpty)
                }
            }
            .sheet(isPresented: $showExercisePicker) {
                ExercisePickerView { exercise in
                    if !selectedExercises.contains(where: { $0.id == exercise.id }) {
                        selectedExercises.append(exercise)
                    }
                }
            }
        }
    }
    
    private func saveTemplate() {
        viewModel.createTemplate(
            name: name,
            description: description.isEmpty ? nil : description,
            exercises: selectedExercises
        )
        dismiss()
    }
}

// MARK: - Template Info
struct TemplateInfo: Identifiable {
    let id: UUID
    let name: String
    let description: String?
    let isSystem: Bool
    let exercises: [TemplateExercise]
    
    struct TemplateExercise {
        let name: String
        let suggestedSets: Int?
        let suggestedReps: Int?
    }
}

#Preview {
    WorkoutTemplateView()
}

