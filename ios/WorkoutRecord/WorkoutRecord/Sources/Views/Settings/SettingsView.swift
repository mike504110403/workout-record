import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                // Profile Section
                Section {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.title)
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("個人資料")
                                    .font(.headline)
                                Text("未登入")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    NavigationLink {
                        GoalSettingsView()
                    } label: {
                        Label("目標設定", systemImage: "target")
                            .foregroundColor(.orange)
                    }
                }
                
                // Exercise Management
                Section("動作庫管理") {
                    NavigationLink {
                        ExerciseManagementView()
                    } label: {
                        Label("動作庫", systemImage: "list.bullet")
                    }
                    
                    NavigationLink {
                        CustomExerciseListView()
                    } label: {
                        Label("自定義動作", systemImage: "plus.circle")
                    }
                }
                
                // Workout Templates
                Section("訓練模板") {
                    NavigationLink {
                        WorkoutTemplateView()
                    } label: {
                        Label("我的模板", systemImage: "doc.text")
                    }
                }
                
                // App Settings
                Section("應用設定") {
                    NavigationLink {
                        AppSettingsView()
                    } label: {
                        Label("偏好設定", systemImage: "gear")
                    }
                    
                    NavigationLink {
                        Text("通知設定")
                    } label: {
                        Label("通知", systemImage: "bell")
                    }
                }
                
                // Data Management
                Section("數據管理") {
                    Button {
                        // TODO: Export data
                    } label: {
                        Label("匯出數據", systemImage: "square.and.arrow.up")
                    }
                    
                    Button {
                        // TODO: Import data
                    } label: {
                        Label("匯入數據", systemImage: "square.and.arrow.down")
                    }
                }
                
                // About
                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    NavigationLink {
                        Text("使用教學")
                    } label: {
                        Label("使用教學", systemImage: "book")
                    }
                    
                    NavigationLink {
                        Text("關於我們")
                    } label: {
                        Label("關於", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("設定")
        }
    }
}

struct ProfileView: View {
    @State private var name = ""
    @State private var email = "user@example.com"
    @State private var height = ""
    @State private var targetWeight = ""
    @State private var weeklyGoal = 4
    @State private var selectedGender: Gender = .notSpecified
    
    enum Gender: String, CaseIterable {
        case male = "男性"
        case female = "女性"
        case notSpecified = "不指定"
    }
    
    var body: some View {
        Form {
            Section("帳號資訊") {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name.isEmpty ? "未設定姓名" : name)
                            .font(.headline)
                        Text(email)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 8)
                }
                .padding(.vertical, 8)
            }
            
            Section("基本資料") {
                TextField("姓名", text: $name)
                
                Picker("性別", selection: $selectedGender) {
                    ForEach(Gender.allCases, id: \.self) { gender in
                        Text(gender.rawValue).tag(gender)
                    }
                }
                
                HStack {
                    TextField("身高", text: $height)
                        .keyboardType(.decimalPad)
                    Text("cm")
                        .foregroundColor(.secondary)
                }
            }
            
            Section("訓練目標") {
                HStack {
                    TextField("目標體重", text: $targetWeight)
                        .keyboardType(.decimalPad)
                    Text("kg")
                        .foregroundColor(.secondary)
                }
                
                Stepper("每週訓練目標: \(weeklyGoal) 次", value: $weeklyGoal, in: 1...7)
            }
            
            Section {
                Button("儲存") {
                    // TODO: Save profile
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("個人資料")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ExerciseManagementView: View {
    let categories = ["胸部", "背部", "腿部", "肩部", "手臂", "核心"]
    
    var body: some View {
        List(categories, id: \.self) { category in
            NavigationLink(category) {
                ExerciseCategoryView(category: category)
            }
        }
        .navigationTitle("動作庫")
    }
}

struct ExerciseCategoryView: View {
    let category: String
    
    // Mock exercises
    let exercises = [
        "槓鈴臥推",
        "啞鈴臥推",
        "上斜臥推",
        "下斜臥推",
        "飛鳥"
    ]
    
    var body: some View {
        List {
            ForEach(exercises, id: \.self) { exercise in
                HStack {
                    Text(exercise)
                    
                    Spacer()
                    
                    Button {
                        // TODO: Toggle favorite
                    } label: {
                        Image(systemName: "star")
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .navigationTitle(category)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    // TODO: Add custom exercise
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

struct AppSettingsView: View {
    @State private var selectedUnit = "kg"
    @State private var selectedTheme = "system"
    @State private var selectedFormula = "epley"
    @State private var defaultRestTime = 90
    @State private var enableAutoRestTimer = true
    @State private var enableHapticFeedback = true
    
    var body: some View {
        Form {
            Section("單位系統") {
                Picker("重量單位", selection: $selectedUnit) {
                    Text("公斤 (kg)").tag("kg")
                    Text("磅 (lb)").tag("lb")
                }
            }
            
            Section("外觀") {
                Picker("主題", selection: $selectedTheme) {
                    Text("淺色").tag("light")
                    Text("深色").tag("dark")
                    Text("跟隨系統").tag("system")
                }
            }
            
            Section("訓練設定") {
                Stepper("預設休息時間: \(defaultRestTime) 秒", value: $defaultRestTime, in: 30...300, step: 15)
                
                Toggle("自動開始休息計時", isOn: $enableAutoRestTimer)
                
                Toggle("震動回饋", isOn: $enableHapticFeedback)
            }
            
            Section("進階設定") {
                Picker("1RM 計算公式", selection: $selectedFormula) {
                    Text("Epley").tag("epley")
                    Text("Brzycki").tag("brzycki")
                    Text("Lander").tag("lander")
                }
                .onChange(of: selectedFormula) { newValue in
                    // Show formula explanation
                }
                
                NavigationLink {
                    FormulaExplanationView()
                } label: {
                    Text("查看公式說明")
                        .font(.caption)
                }
            }
            
            Section {
                Button("重置所有設定") {
                    // TODO: Reset settings
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("偏好設定")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FormulaExplanationView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Epley 公式")
                        .font(.headline)
                    Text("1RM = 重量 × (1 + 次數 / 30)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("最常用的公式，適合大多數情況。")
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Brzycki 公式")
                        .font(.headline)
                    Text("1RM = 重量 × (36 / (37 - 次數))")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("較保守的估算，適合次數較少的情況。")
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lander 公式")
                        .font(.headline)
                    Text("1RM = 重量 × (100 / (101.3 - 2.67123 × 次數))")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("適合高次數的訓練估算。")
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("1RM 公式說明")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
}

