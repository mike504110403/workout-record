import SwiftUI

/// 新手教學頁面
struct TutorialView: View {
    @State private var currentStep = 0
    @Environment(\.dismiss) private var dismiss
    
    private let tutorialSteps = [
        TutorialStep(
            title: "歡迎使用健身記錄 App",
            description: "讓我們快速了解如何使用這個 App 來追蹤您的健身進度",
            image: "figure.walk",
            color: .blue
        ),
        TutorialStep(
            title: "開始您的第一次訓練",
            description: "點擊「開始訓練」按鈕，選擇動作並記錄您的組數和重量",
            image: "dumbbell.fill",
            color: .orange
        ),
        TutorialStep(
            title: "記錄您的體重",
            description: "定期記錄體重變化，App 會幫您分析趨勢",
            image: "scalemass.fill",
            color: .green
        ),
        TutorialStep(
            title: "查看您的數據",
            description: "在「數據」頁面查看訓練容量、個人記錄和成就",
            image: "chart.bar.fill",
            color: .purple
        ),
        TutorialStep(
            title: "設定您的目標",
            description: "在設定中設定您的健身目標，讓 App 更好地為您服務",
            image: "target",
            color: .red
        )
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 進度指示器
                ProgressView(value: Double(currentStep + 1), total: Double(tutorialSteps.count))
                    .progressViewStyle(LinearProgressViewStyle())
                    .padding()
                
                // 教學內容
                TabView(selection: $currentStep) {
                    ForEach(0..<tutorialSteps.count, id: \.self) { index in
                        TutorialStepView(step: tutorialSteps[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // 控制按鈕
                HStack {
                    if currentStep > 0 {
                        Button("上一步") {
                            withAnimation {
                                currentStep -= 1
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Spacer()
                    
                    if currentStep < tutorialSteps.count - 1 {
                        Button("下一步") {
                            withAnimation {
                                currentStep += 1
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("開始使用") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
            .navigationTitle("新手教學")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("跳過") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct TutorialStepView: View {
    let step: TutorialStep
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // 圖示
            Image(systemName: step.image)
                .font(.system(size: 80))
                .foregroundColor(step.color)
            
            // 標題
            Text(step.title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            // 描述
            Text(step.description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
        }
        .padding()
    }
}

struct TutorialStep {
    let title: String
    let description: String
    let image: String
    let color: Color
}

#Preview {
    TutorialView()
}
