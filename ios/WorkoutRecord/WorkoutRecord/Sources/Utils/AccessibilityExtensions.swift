import SwiftUI

// MARK: - Accessibility Extensions

extension View {
    /// 添加無障礙標籤
    func accessibilityLabel(_ label: String) -> some View {
        self.accessibilityLabel(Text(label))
    }
    
    /// 添加無障礙提示
    func accessibilityHint(_ hint: String) -> some View {
        self.accessibilityHint(Text(hint))
    }
    
    /// 添加無障礙值
    func accessibilityValue(_ value: String) -> some View {
        self.accessibilityValue(Text(value))
    }
    
    /// 設定無障礙調整動作
    func accessibilityAdjustableAction(_ action: @escaping (AccessibilityAdjustmentDirection) -> Void) -> some View {
        self.accessibilityAdjustableAction { direction in
            action(direction)
        }
    }
}

// MARK: - Workout Accessibility

extension View {
    /// 訓練記錄的無障礙支援
    func workoutAccessibility(workout: WorkoutSummary) -> some View {
        self
            .accessibilityLabel("訓練記錄")
            .accessibilityValue("\(workout.date.formatted(date: .abbreviated, time: .shortened))，\(workout.exercisesCount)個動作，\(workout.totalSets)組，總容量\(String(format: "%.0f", workout.totalVolume))公斤，持續\(workout.duration)分鐘")
            .accessibilityHint("點擊查看詳細資訊")
    }
    
    /// 動作的無障礙支援
    func exerciseAccessibility(exercise: Exercise) -> some View {
        self
            .accessibilityLabel("\(exercise.name)")
            .accessibilityValue("\(exercise.muscleGroups.first ?? "未知")部位動作")
            .accessibilityHint("點擊選擇此動作")
    }
    
    /// 體重記錄的無障礙支援
    func bodyWeightAccessibility(weight: Double, date: Date) -> some View {
        self
            .accessibilityLabel("體重記錄")
            .accessibilityValue("\(String(format: "%.1f", weight))公斤，記錄於\(date.formatted(date: .abbreviated, time: .shortened))")
    }
    
    /// 成就的無障礙支援
    func achievementAccessibility(achievement: Achievement) -> some View {
        self
            .accessibilityLabel("成就")
            .accessibilityValue("\(achievement.title)，\(achievement.description)")
            .accessibilityHint(achievement.isUnlocked ? "已解鎖" : "未解鎖")
    }
}

// MARK: - Chart Accessibility

extension View {
    /// 圖表的無障礙支援
    func chartAccessibility(title: String, data: [String: Double]) -> some View {
        let dataDescription = data.map { "\($0.key): \(String(format: "%.1f", $0.value))" }.joined(separator: ", ")
        
        return self
            .accessibilityLabel("\(title)圖表")
            .accessibilityValue(dataDescription)
            .accessibilityHint("圖表顯示數據趨勢")
    }
}

// MARK: - Button Accessibility

extension View {
    /// 按鈕的無障礙支援
    func buttonAccessibility(label: String, hint: String? = nil) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "點擊執行操作")
    }
    
    /// 切換按鈕的無障礙支援
    func toggleAccessibility(label: String, isOn: Bool, hint: String? = nil) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityValue(isOn ? "開啟" : "關閉")
            .accessibilityHint(hint ?? "點擊切換狀態")
    }
}

// MARK: - Form Accessibility

extension View {
    /// 表單輸入的無障礙支援
    func formFieldAccessibility(label: String, value: String, hint: String? = nil) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityValue(value.isEmpty ? "未輸入" : value)
            .accessibilityHint(hint ?? "輸入\(label)")
    }
}

// MARK: - Navigation Accessibility

extension View {
    /// 導航連結的無障礙支援
    func navigationAccessibility(destination: String) -> some View {
        self
            .accessibilityLabel("前往\(destination)")
            .accessibilityHint("點擊導航到\(destination)頁面")
    }
}

// MARK: - Accessibility Utilities

struct AccessibilityHelper {
    /// 生成訓練數據的語音描述
    static func workoutDescription(workout: WorkoutSummary) -> String {
        let dateString = workout.date.formatted(date: .abbreviated, time: .shortened)
        let exercisesString = workout.exercisesCount == 1 ? "1個動作" : "\(workout.exercisesCount)個動作"
        let setsString = workout.totalSets == 1 ? "1組" : "\(workout.totalSets)組"
        let volumeString = String(format: "%.0f", workout.totalVolume)
        let durationString = workout.duration == 1 ? "1分鐘" : "\(workout.duration)分鐘"
        
        return "訓練記錄，\(dateString)，\(exercisesString)，\(setsString)，總容量\(volumeString)公斤，持續\(durationString)"
    }
    
    /// 生成體重數據的語音描述
    static func bodyWeightDescription(weight: Double, date: Date) -> String {
        let weightString = String(format: "%.1f", weight)
        let dateString = date.formatted(date: .abbreviated, time: .shortened)
        return "體重\(weightString)公斤，記錄於\(dateString)"
    }
    
    /// 生成成就的語音描述
    static func achievementDescription(achievement: Achievement) -> String {
        let status = achievement.isUnlocked ? "已解鎖" : "未解鎖"
        return "成就，\(achievement.title)，\(achievement.description)，狀態：\(status)"
    }
    
    /// 生成圖表的語音描述
    static func chartDescription(title: String, data: [String: Double]) -> String {
        let dataString = data.map { "\($0.key) \(String(format: "%.1f", $0.value))" }.joined(separator: "，")
        return "\(title)圖表，數據：\(dataString)"
    }
}

// MARK: - VoiceOver Support

struct VoiceOverSupport {
    /// 為 VoiceOver 用戶提供額外的語音提示
    static func announce(_ message: String) {
        DispatchQueue.main.async {
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }
    
    /// 為 VoiceOver 用戶提供螢幕更新通知
    static func screenChanged() {
        DispatchQueue.main.async {
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }
    
    /// 為 VoiceOver 用戶提供佈局更新通知
    static func layoutChanged() {
        DispatchQueue.main.async {
            UIAccessibility.post(notification: .layoutChanged, argument: nil)
        }
    }
}

// MARK: - Dynamic Type Support

extension View {
}

// MARK: - Accessibility Settings View

struct AccessibilitySettingsView: View {
    @State private var voiceOverEnabled = false
    @State private var reduceMotion = false
    @State private var increaseContrast = false
    @State private var largerText = false
    
    var body: some View {
        NavigationStack {
            List {
                Section("無障礙功能") {
                    Toggle("VoiceOver 支援", isOn: $voiceOverEnabled)
                    Toggle("減少動畫", isOn: $reduceMotion)
                    Toggle("增加對比度", isOn: $increaseContrast)
                    Toggle("較大字體", isOn: $largerText)
                }
                
                Section("語音設定") {
                    NavigationLink {
                        VoiceSettingsView()
                    } label: {
                        Label("語音設定", systemImage: "speaker.wave.2")
                    }
                }
                
                Section("測試功能") {
                    Button("測試語音提示") {
                        VoiceOverSupport.announce("這是語音提示測試")
                    }
                    
                    Button("測試螢幕更新") {
                        VoiceOverSupport.screenChanged()
                    }
                }
            }
            .navigationTitle("無障礙設定")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct VoiceSettingsView: View {
    @State private var speechRate: Double = 0.5
    @State private var speechPitch: Double = 1.0
    @State private var speechVolume: Double = 1.0
    
    var body: some View {
        List {
            Section("語音設定") {
                VStack(alignment: .leading) {
                    Text("語音速度")
                    Slider(value: $speechRate, in: 0.1...1.0)
                    Text("\(String(format: "%.1f", speechRate))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading) {
                    Text("語音音調")
                    Slider(value: $speechPitch, in: 0.5...2.0)
                    Text("\(String(format: "%.1f", speechPitch))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading) {
                    Text("語音音量")
                    Slider(value: $speechVolume, in: 0.1...1.0)
                    Text("\(String(format: "%.1f", speechVolume))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section("測試") {
                Button("播放測試語音") {
                    // 這裡可以實作語音合成功能
                }
            }
        }
        .navigationTitle("語音設定")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    AccessibilitySettingsView()
}
