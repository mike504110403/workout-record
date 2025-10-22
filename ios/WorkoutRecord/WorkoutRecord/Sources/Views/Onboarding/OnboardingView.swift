import SwiftUI

/// 首次啟動引導流程
struct OnboardingView: View {
    @ObservedObject var state: OnboardingState
    
    var body: some View {
        VStack(spacing: 0) {
            // 進度指示器
            ProgressIndicator(currentStep: state.currentStep, totalSteps: 4)
                .padding(.top, 20)
            
            // 頁面內容
            TabView(selection: $state.currentStep) {
                WelcomeStep()
                    .tag(0)
                
                BasicInfoStep(state: state)
                    .tag(1)
                
                GoalStep(state: state)
                    .tag(2)
                
                CompletionStep(state: state)
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: state.currentStep)
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Progress Indicator

struct ProgressIndicator: View {
    let currentStep: Int
    let totalSteps: Int
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Step 1: Welcome

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 100))
                .foregroundColor(.blue)
            
            VStack(spacing: 16) {
                Text("歡迎使用 WorkoutRecord")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("專為健身愛好者打造的\n智能訓練記錄工具")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "數據分析",
                    description: "追蹤訓練容量與 PR 進步"
                )
                
                FeatureRow(
                    icon: "target",
                    title: "目標管理",
                    description: "設定並追蹤訓練目標"
                )
                
                FeatureRow(
                    icon: "icloud",
                    title: "雲端同步",
                    description: "數據安全備份（即將推出）"
                )
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding()
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Step 2: Basic Info

struct BasicInfoStep: View {
    @ObservedObject var state: OnboardingState
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Text("基本資訊")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("幫助我們更了解你")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                
                VStack(spacing: 20) {
                    // 當前體重
                    VStack(alignment: .leading, spacing: 8) {
                        Text("當前體重 *")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        HStack {
                            TextField("請輸入體重", text: $state.weight)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .font(.title2)
                            
                            Text("kg")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    
                    // 性別
                    VStack(alignment: .leading, spacing: 8) {
                        Text("性別")
                            .font(.headline)
                        
                        Picker("性別", selection: $state.gender) {
                            Text("男性").tag("男性")
                            Text("女性").tag("女性")
                            Text("不指定").tag("不指定")
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    
                    // 年齡（選填）
                    VStack(alignment: .leading, spacing: 8) {
                        Text("年齡（選填）")
                            .font(.headline)
                        
                        TextField("請輸入年齡", text: $state.age)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Step 3: Goal

struct GoalStep: View {
    @ObservedObject var state: OnboardingState
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Text("設定目標")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("明確的目標讓你更有動力")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                
                VStack(spacing: 20) {
                    // 目標體重
                    VStack(alignment: .leading, spacing: 8) {
                        Text("目標體重（選填）")
                            .font(.headline)
                        
                        HStack {
                            TextField("理想體重", text: $state.targetWeight)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .font(.title2)
                            
                            Text("kg")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        
                        if let current = Double(state.weight),
                           let target = Double(state.targetWeight) {
                            let diff = target - current
                            Text(diff > 0 ? "需增重 \(String(format: "%.1f", diff)) kg" : "需減重 \(String(format: "%.1f", abs(diff))) kg")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    
                    // 週訓練目標
                    VStack(alignment: .leading, spacing: 12) {
                        Text("每週訓練目標")
                            .font(.headline)
                        
                        Stepper(
                            value: $state.weeklyGoal,
                            in: 1...7
                        ) {
                            HStack {
                                Text("\(state.weeklyGoal) 次 / 週")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                
                                Spacer()
                            }
                        }
                        
                        Text(goalDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                
                Spacer(minLength: 60)
            }
        }
    }
    
    private var goalDescription: String {
        switch state.weeklyGoal {
        case 1...2: return "輕度訓練，適合新手入門"
        case 3...4: return "中等訓練，穩定進步"
        case 5...6: return "高強度訓練，快速成長"
        default: return "專業級訓練，全力衝刺"
        }
    }
}

// MARK: - Step 4: Completion

struct CompletionStep: View {
    @ObservedObject var state: OnboardingState
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 100))
                .foregroundColor(.green)
            
            VStack(spacing: 16) {
                Text("一切準備就緒！")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("開始記錄你的健身旅程")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                if let weight = Double(state.weight) {
                    InfoRow(label: "當前體重", value: "\(String(format: "%.1f", weight)) kg")
                }
                
                InfoRow(label: "性別", value: state.gender)
                
                if !state.age.isEmpty {
                    InfoRow(label: "年齡", value: state.age)
                }
                
                if let target = Double(state.targetWeight) {
                    InfoRow(label: "目標體重", value: "\(String(format: "%.1f", target)) kg")
                }
                
                InfoRow(label: "週訓練目標", value: "\(state.weeklyGoal) 次")
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal, 40)
            
            Button {
                state.complete()
            } label: {
                Text("開始使用")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding()
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    OnboardingView(state: OnboardingState())
}

