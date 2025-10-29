import SwiftUI
import Combine

// MARK: - Onboarding Steps

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case basicInfo = 1
    case goals = 2
    case features = 3
    case complete = 4
    
    var title: String {
        switch self {
        case .welcome: return "歡迎使用健身記錄"
        case .basicInfo: return "基本資訊"
        case .goals: return "設定目標"
        case .features: return "主要功能"
        case .complete: return "準備就緒"
        }
    }
    
    var description: String {
        switch self {
        case .welcome: return "讓我們快速了解如何使用這個應用程式來追蹤你的健身進度"
        case .basicInfo: return "請輸入你的基本資訊，幫助我們提供更好的訓練建議"
        case .goals: return "設定你的健身目標，讓訓練更有方向"
        case .features: return "應用程式提供完整的健身記錄功能，包括訓練記錄、進度追蹤和成就系統"
        case .complete: return "你已經準備好開始你的健身之旅了！"
        }
    }
    
    var icon: String {
        switch self {
        case .welcome: return "hand.wave.fill"
        case .basicInfo: return "person.fill"
        case .goals: return "target"
        case .features: return "star.fill"
        case .complete: return "checkmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .welcome: return .blue
        case .basicInfo: return .purple
        case .goals: return .orange
        case .features: return .green
        case .complete: return .green
        }
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    @State private var currentStep = OnboardingStep.welcome
    
    // 驗證當前步驟是否可以繼續
    private var canProceed: Bool {
        switch currentStep {
        case .welcome, .features, .complete:
            return true
        case .basicInfo:
            // 必須填寫體重
            return !onboardingState.weight.isEmpty && Double(onboardingState.weight) != nil
        case .goals:
            return true // 目標設定是可選的
        }
    }
    
    var body: some View {
        ZStack {
            // 背景
            LinearGradient(
                gradient: Gradient(colors: [currentStep.color.opacity(0.1), Color.clear]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 內容區域
                TabView(selection: $currentStep) {
                    ForEach(OnboardingStep.allCases, id: \.self) { step in
                        if step == .basicInfo {
                            BasicInfoFormView()
                                .environmentObject(onboardingState)
                                .tag(step)
                        } else if step == .goals {
                            GoalsFormView()
                                .environmentObject(onboardingState)
                                .tag(step)
                        } else {
                            OnboardingStepView(step: step)
                                .tag(step)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .animation(.easeInOut, value: currentStep)
                
                // 底部控制區域
                VStack(spacing: 16) {
                    // 滑動提示（僅在可以滑動且非最後一步時顯示）
                    if currentStep != .complete && canProceed {
                        HStack(spacing: 6) {
                            Text("向左滑動繼續")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.left")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .opacity(0.6)
                    }
                    
                    // 完成按鈕（僅在最後一步顯示）
                    if currentStep == .complete {
                        Button("開始使用") {
                            onboardingState.complete()
                        }
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(currentStep.color)
                        .cornerRadius(12)
                        .padding(.horizontal)
                    } else {
                        // 跳過按鈕
                        Button("跳過教學") {
                            onboardingState.complete()
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom)
            }
        }
        .onAppear {
            currentStep = OnboardingStep(rawValue: onboardingState.currentStep) ?? .welcome
        }
        .onChange(of: currentStep) { oldValue, newValue in
            // 檢查是否可以切換到下一步
            let oldCanProceed: Bool
            switch oldValue {
            case .welcome, .features, .complete:
                oldCanProceed = true
            case .basicInfo:
                oldCanProceed = !onboardingState.weight.isEmpty
            case .goals:
                oldCanProceed = true // 目標頁面都是選填
            }
            
            // 如果從需要驗證的頁面切換且資料未填完，則阻止切換
            if !oldCanProceed && newValue.rawValue > oldValue.rawValue {
                // 切換回原來的步驟
                DispatchQueue.main.async {
                    currentStep = oldValue
                }
            } else {
                // 更新狀態
                onboardingState.currentStep = newValue.rawValue
            }
        }
    }
}

// MARK: - Onboarding Step View

struct OnboardingStepView: View {
    let step: OnboardingStep
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // 圖標
            Image(systemName: step.icon)
                .font(.system(size: 80))
                .foregroundColor(step.color)
                .scaleEffect(1.0)
                .animation(.easeInOut(duration: 0.5), value: step)
            
            // 標題和描述
            VStack(spacing: 16) {
                Text(step.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(step.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }
            
            // 步驟特定內容
            stepSpecificContent
            
            Spacer()
        }
        .padding(.horizontal, 32)
    }
    
    @ViewBuilder
    private var stepSpecificContent: some View {
        switch step {
        case .welcome:
            VStack(spacing: 16) {
                FeatureCard(
                    icon: "figure.strengthtraining.traditional",
                    title: "記錄訓練",
                    description: "輕鬆記錄每次訓練的詳細數據"
                )
                
                FeatureCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "追蹤進度",
                    description: "查看你的訓練進度和個人記錄"
                )
                
                FeatureCard(
                    icon: "trophy.fill",
                    title: "成就系統",
                    description: "解鎖各種成就，激勵持續訓練"
                )
            }
            
        case .basicInfo:
            EmptyView() // 將在 OnboardingView 中直接處理表單
            
        case .goals:
            EmptyView() // 將在 OnboardingView 中直接處理表單
            
        case .features:
            VStack(spacing: 20) {
                FeatureGrid()
            }
            
        case .complete:
            VStack(spacing: 20) {
                CompleteView()
            }
        }
    }
}

// MARK: - Supporting Views

struct FeatureCard: View {
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
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct FeatureGrid: View {
    let features = [
        ("figure.strengthtraining.traditional", "訓練記錄", "記錄每次訓練"),
        ("chart.bar.fill", "數據分析", "查看訓練統計"),
        ("calendar", "計劃安排", "規劃訓練計劃"),
        ("trophy.fill", "成就系統", "解鎖各種成就"),
        ("target", "目標設定", "設定健身目標"),
        ("icloud.fill", "雲端同步", "跨設備同步數據")
    ]
    
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
            ForEach(features, id: \.0) { feature in
                VStack(spacing: 8) {
                    Image(systemName: feature.0)
                        .font(.title2)
                        .foregroundColor(.blue)
                    
                    Text(feature.1)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(feature.2)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
        }
    }
}

struct WorkoutDemoView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("如何開始訓練")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                StepItem(number: 1, title: "點擊「開始訓練」", description: "選擇空白訓練或使用模板")
                StepItem(number: 2, title: "新增動作", description: "選擇要訓練的動作")
                StepItem(number: 3, title: "記錄組數", description: "輸入重量、次數和組數")
                StepItem(number: 4, title: "完成訓練", description: "查看訓練報告和統計")
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct TrackingDemoView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("追蹤你的進度")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack(spacing: 20) {
                VStack {
                    Text("150")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text("總訓練次數")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text("2,500")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("總容量 (kg)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text("15")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    Text("個人記錄")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct GoalsDemoView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("設定你的目標")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                GoalItem(icon: "target", title: "每週訓練 4 次", isCompleted: true)
                GoalItem(icon: "chart.bar.fill", title: "深蹲達到 100kg", isCompleted: false)
                GoalItem(icon: "flame.fill", title: "連續訓練 30 天", isCompleted: false)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct CompleteView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("🎉 準備就緒！")
                .font(.title)
                .fontWeight(.bold)
            
            Text("你已經了解了所有主要功能，現在可以開始你的健身之旅了！")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 8) {
                Text("💡 小提示")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("記得定期記錄訓練數據，這樣才能更好地追蹤你的進步！")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

struct StepItem: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.blue)
                .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

struct GoalItem: View {
    let icon: String
    let title: String
    let isCompleted: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(isCompleted ? .green : .blue)
            
            Text(title)
                .font(.subheadline)
            
            Spacer()
            
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isCompleted ? .green : .gray)
        }
    }
}

// MARK: - Onboarding Modifier

struct OnboardingModifier: ViewModifier {
    @EnvironmentObject private var onboardingState: OnboardingState
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: .constant(!onboardingState.hasCompleted)) {
                OnboardingView()
                    .environmentObject(onboardingState)
                    .dismissOnTapSheet {
                        onboardingState.complete()
                    }
            }
    }
}

extension View {
    func onboarding() -> some View {
        modifier(OnboardingModifier())
    }
}

// MARK: - Form Views

struct BasicInfoFormView: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    @StateObject private var globalSettings = GlobalSettingsManager.shared
    @FocusState private var focusedField: Field?
    
    enum Field {
        case weight, height, age
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                Spacer()
                
                // 圖標
                Image(systemName: "person.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.purple)
                
                // 標題和描述
                VStack(spacing: 16) {
                    Text("基本資訊")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text("請輸入你的基本資訊，幫助我們提供更好的訓練建議")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                }
                
                // 表單
                VStack(spacing: 20) {
                    // 體重（必填）
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("當前體重")
                                .font(.headline)
                            Text("*")
                                .foregroundColor(.red)
                        }
                        
                        HStack {
                            TextField("請輸入體重", text: $onboardingState.weight)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .weight)
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                            
                            Text(globalSettings.weightUnit.symbol)
                                .foregroundColor(.secondary)
                                .padding(.trailing)
                        }
                    }
                    
                    // 身高（選填）
                    VStack(alignment: .leading, spacing: 8) {
                        Text("身高")
                            .font(.headline)
                        
                        HStack {
                            TextField("請輸入身高（選填）", text: $onboardingState.height)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .height)
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                            
                            Text("cm")
                                .foregroundColor(.secondary)
                                .padding(.trailing)
                        }
                    }
                    
                    // 性別
                    VStack(alignment: .leading, spacing: 8) {
                        Text("性別")
                            .font(.headline)
                        
                        Picker("性別", selection: $onboardingState.gender) {
                            Text("不指定").tag("不指定")
                            Text("男性").tag("男性")
                            Text("女性").tag("女性")
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // 年齡（選填）
                    VStack(alignment: .leading, spacing: 8) {
                        Text("年齡")
                            .font(.headline)
                        
                        TextField("請輸入年齡（選填）", text: $onboardingState.age)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .age)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.horizontal, 32)
        }
        .dismissOnTap {
            focusedField = nil
        }
    }
}

struct GoalsFormView: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    @StateObject private var globalSettings = GlobalSettingsManager.shared
    @FocusState private var focusedField: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                Spacer()
                
                // 圖標
                Image(systemName: "target")
                    .font(.system(size: 80))
                    .foregroundColor(.orange)
                
                // 標題和描述
                VStack(spacing: 16) {
                    Text("設定目標")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text("設定你的健身目標，讓訓練更有方向")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                }
                
                // 表單
                VStack(spacing: 20) {
                    // 目標體重（選填）
                    VStack(alignment: .leading, spacing: 8) {
                        Text("目標體重")
                            .font(.headline)
                        
                        HStack {
                            TextField("請輸入目標體重（選填）", text: $onboardingState.targetWeight)
                                .keyboardType(.decimalPad)
                                .focused($focusedField)
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                            
                            Text(globalSettings.weightUnit.symbol)
                                .foregroundColor(.secondary)
                                .padding(.trailing)
                        }
                    }
                    
                    // 每週訓練次數
                    VStack(alignment: .leading, spacing: 8) {
                        Text("每週訓練目標")
                            .font(.headline)
                        
                        VStack(spacing: 12) {
                            HStack {
                                Text("每週訓練")
                                Spacer()
                                Text("\(onboardingState.weeklyGoal) 次")
                                    .foregroundColor(.blue)
                                    .fontWeight(.semibold)
                            }
                            
                            Stepper("", value: $onboardingState.weeklyGoal, in: 1...7)
                                .labelsHidden()
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    
                    // 提示訊息
                    VStack(spacing: 8) {
                        Text("💡 小提示")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("這些目標可以之後在設定中修改，不用擔心！")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.horizontal, 32)
        }
        .dismissOnTap {
            focusedField = false
        }
    }
}

#Preview {
    OnboardingView()
}