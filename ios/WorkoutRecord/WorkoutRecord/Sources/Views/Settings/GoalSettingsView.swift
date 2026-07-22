import SwiftUI

struct GoalSettingsView: View {
    @StateObject private var viewModel = GoalViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                // 訓練目標
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("週訓練次數目標")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Stepper(value: $viewModel.weeklyWorkoutGoal, in: 1...7) {
                            HStack {
                                Text("\(viewModel.weeklyWorkoutGoal)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Text("次/週")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Label("訓練目標", systemImage: "target")
                }
                
                // 體重目標
                Section {
                    HStack {
                        Text("目標體重")
                        Spacer()
                        TextField("未設定", text: $viewModel.targetWeight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("kg")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("體重目標", systemImage: "figure.walk")
                } footer: {
                    Text("不填寫則不顯示目標體重線")
                        .font(.caption)
                }
                
                // 容量目標
                Section {
                    VolumeGoalRow(
                        muscleGroup: "胸部",
                        icon: "",
                        value: $viewModel.chestVolumeGoal
                    )
                    
                    VolumeGoalRow(
                        muscleGroup: "背部",
                        icon: "",
                        value: $viewModel.backVolumeGoal
                    )
                    
                    VolumeGoalRow(
                        muscleGroup: "腿部",
                        icon: "",
                        value: $viewModel.legsVolumeGoal
                    )
                    
                    VolumeGoalRow(
                        muscleGroup: "肩部",
                        icon: "",
                        value: $viewModel.shouldersVolumeGoal
                    )
                    
                    VolumeGoalRow(
                        muscleGroup: "手臂",
                        icon: "",
                        value: $viewModel.armsVolumeGoal
                    )
                    
                    VolumeGoalRow(
                        muscleGroup: "核心",
                        icon: "",
                        value: $viewModel.coreVolumeGoal
                    )
                } header: {
                    Label("週容量目標", systemImage: "chart.bar.fill")
                } footer: {
                    Text("設定各肌群的週訓練容量目標（公斤），不填寫則不追蹤")
                        .font(.caption)
                }
                
                // 提醒設定
                Section {
                    Toggle(isOn: $viewModel.restDayReminder) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("休息日提醒")
                                .font(.body)
                            Text("連續休息 2 天後提醒")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Label("提醒設定", systemImage: "bell.fill")
                } footer: {
                    Text("未來版本將支持推播通知")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .navigationTitle("目標設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        viewModel.saveGoals()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(viewModel.isSaving)
                }
            }
            .alert("保存成功", isPresented: $viewModel.showSuccessMessage) {
                Button("確定", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("目標已更新")
            }
            .alert("錯誤", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("確定", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
        }
    }
}

// MARK: - Volume Goal Row
private struct VolumeGoalRow: View {
    let muscleGroup: String
    let icon: String
    @Binding var value: String
    
    var body: some View {
        HStack {
            if !icon.isEmpty {
                Text(icon)
            }
            Text(muscleGroup)
            Spacer()
            TextField("未設定", text: $value)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
            Text("kg/週")
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }
}

// MARK: - Preview
#Preview {
    GoalSettingsView()
}

