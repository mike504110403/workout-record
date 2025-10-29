import SwiftUI
import Combine

/// 新手教學管理器
@MainActor
class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()
    
    @Published var isOnboardingComplete = false
    @Published var currentStep = 0
    @Published var showOnboarding = false
    
    private let userDefaults = UserDefaults.standard
    private let onboardingKey = "OnboardingComplete"
    
    private init() {
        loadOnboardingState()
    }
    
    // MARK: - Onboarding State Management
    
    private func loadOnboardingState() {
        isOnboardingComplete = userDefaults.bool(forKey: onboardingKey)
        
        if !isOnboardingComplete {
            showOnboarding = true
        }
    }
    
    func completeOnboarding() {
        isOnboardingComplete = true
        showOnboarding = false
        userDefaults.set(true, forKey: onboardingKey)
    }
    
    func resetOnboarding() {
        isOnboardingComplete = false
        showOnboarding = true
        currentStep = 0
        userDefaults.removeObject(forKey: onboardingKey)
    }
    
    func nextStep() {
        if currentStep < OnboardingStep.allCases.count - 1 {
            currentStep += 1
        } else {
            completeOnboarding()
        }
    }
    
    func previousStep() {
        if currentStep > 0 {
            currentStep -= 1
        }
    }
    
    func skipOnboarding() {
        completeOnboarding()
    }
}

// MARK: - Onboarding Steps

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case features = 1
    case workout = 2
    case tracking = 3
    case goals = 4
    case complete = 5
    
    var title: String {
        switch self {
        case .welcome: return "歡迎使用健身記錄"
        case .features: return "主要功能"
        case .workout: return "開始訓練"
        case .tracking: return "記錄數據"
        case .goals: return "設定目標"
        case .complete: return "準備就緒"
        }
    }
    
    var description: String {
        switch self {
        case .welcome: return "讓我們快速了解如何使用這個應用程式來追蹤你的健身進度"
        case .features: return "應用程式提供完整的健身記錄功能，包括訓練記錄、進度追蹤和成就系統"
        case .workout: return "開始你的第一次訓練，記錄重量、次數和組數"
        case .tracking: return "追蹤你的訓練進度，查看個人記錄和統計數據"
        case .goals: return "設定你的健身目標，讓訓練更有方向"
        case .complete: return "你已經準備好開始你的健身之旅了！"
        }
    }
    
    var icon: String {
        switch self {
        case .welcome: return "hand.wave.fill"
        case .features: return "star.fill"
        case .workout: return "figure.strengthtraining.traditional"
        case .tracking: return "chart.line.uptrend.xyaxis"
        case .goals: return "target"
        case .complete: return "checkmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .welcome: return .blue
        case .features: return .purple
        case .workout: return .green
        case .tracking: return .orange
        case .goals: return .red
        case .complete: return .green
        }
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    @State private var currentStep = OnboardingStep.welcome
    
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
                        OnboardingStepView(step: step)
                            .tag(step)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentStep)
                
                // 底部控制區域
                VStack(spacing: 20) {
                    // 頁面指示器
                    HStack(spacing: 8) {
                        ForEach(OnboardingStep.allCases, id: \.self) { step in
                            Circle()
                                .fill(step == currentStep ? currentStep.color : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                                .animation(.easeInOut, value: currentStep)
                        }
                    }
                    
                    // 按鈕區域
                    HStack(spacing: 16) {
                        if currentStep != .welcome {
                            Button("上一步") {
                                withAnimation {
                                    if let previousStep = OnboardingStep(rawValue: currentStep.rawValue - 1) {
                                        currentStep = previousStep
                                    }
                                }
                            }
                            .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
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
                        } else {
                            Button("下一步") {
                                withAnimation {
                                    if let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) {
                                        currentStep = nextStep
                                    }
                                }
                            }
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(currentStep.color)
                            .cornerRadius(12)
                        }
                    }
                    
                    // 跳過按鈕
                    if currentStep != .complete {
                        Button("跳過教學") {
                            onboardingState.complete()
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
        }
        .onAppear {
            currentStep = OnboardingStep(rawValue: onboardingState.currentStep) ?? .welcome
        }
        .onChange(of: currentStep) { _, newValue in
            onboardingState.currentStep = newValue.rawValue
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
            
        case .features:
            VStack(spacing: 20) {
                FeatureGrid()
            }
            
        case .workout:
            VStack(spacing: 20) {
                WorkoutDemoView()
            }
            
        case .tracking:
            VStack(spacing: 20) {
                TrackingDemoView()
            }
            
        case .goals:
            VStack(spacing: 20) {
                GoalsDemoView()
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

#Preview {
    OnboardingView()
}