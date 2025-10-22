import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appleIDAuth: AppleIDAuthService
    @State private var showSignOutAlert = false
    
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
                                Text(appleIDAuth.userName ?? "未登入")
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
                        SettingsExerciseManagementView()
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
                        CloudKitSettingsView()
                    } label: {
                        Label("iCloud 同步", systemImage: "icloud")
                    }
                    
                    
                    NavigationLink {
                        AppSettingsView()
                    } label: {
                        Label("偏好設定", systemImage: "gear")
                    }
                    
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("通知", systemImage: "bell")
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
                        AboutView()
                    } label: {
                        Label("關於", systemImage: "info.circle")
                    }
                }
                
                // 登出選項
                Section {
                    Button("登出") {
                        showSignOutAlert = true
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("設定")
            .alert("登出", isPresented: $showSignOutAlert) {
                Button("取消", role: .cancel) { }
                Button("登出", role: .destructive) {
                    appleIDAuth.signOut()
                }
            } message: {
                Text("確定要登出嗎？")
            }
        }
    }
}

struct ProfileView: View {
    @StateObject private var profile = UserProfile.shared
    @State private var showSaveAlert = false
    @EnvironmentObject private var appleIDAuth: AppleIDAuthService
    
    enum Gender: String, CaseIterable {
        case male = "男性"
        case female = "女性"
        case notSpecified = "不指定"
    }
    
    var selectedGender: Binding<Gender> {
        Binding(
            get: {
                Gender(rawValue: profile.gender) ?? .notSpecified
            },
            set: { newValue in
                profile.gender = newValue.rawValue
            }
        )
    }
    
    var body: some View {
        Form {
            Section("帳號資訊") {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appleIDAuth.userName ?? "未設定姓名")
                            .font(.headline)
                        Text(appleIDAuth.userEmail ?? "未提供電子郵件")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 8)
                }
                .padding(.vertical, 8)
            }
            
            Section("基本資料") {
                TextField("姓名", text: $profile.name)
                
                Picker("性別", selection: selectedGender) {
                    ForEach(Gender.allCases, id: \.self) { gender in
                        Text(gender.rawValue).tag(gender)
                    }
                }
                
                HStack {
                    TextField("身高", value: $profile.height, format: .number)
                        .keyboardType(.decimalPad)
                    Text("cm")
                        .foregroundColor(.secondary)
                }
            }
            
            Section("訓練目標") {
                HStack {
                    TextField("目標體重", value: $profile.targetWeight, format: .number)
                        .keyboardType(.decimalPad)
                    Text("kg")
                        .foregroundColor(.secondary)
                }
                
                Stepper("每週訓練目標: \(profile.weeklyGoal) 次", value: $profile.weeklyGoal, in: 1...7)
            }
            
            Section {
                Button("儲存") {
                    profile.save()
                    showSaveAlert = true
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("個人資料")
        .navigationBarTitleDisplayMode(.inline)
        .alert("儲存成功", isPresented: $showSaveAlert) {
            Button("確定", role: .cancel) { }
        } message: {
            Text("個人資料已更新")
        }
    }
}

struct SettingsExerciseManagementView: View {
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
    @StateObject private var settings = AppSettings.shared
    @State private var showResetAlert = false
    
    var body: some View {
        Form {
            Section("單位系統") {
                Picker("重量單位", selection: $settings.weightUnit) {
                    Text("公斤 (kg)").tag("kg")
                    Text("磅 (lb)").tag("lb")
                }
            }
            
            Section("外觀") {
                Picker("主題", selection: $settings.theme) {
                    Text("淺色").tag("light")
                    Text("深色").tag("dark")
                    Text("跟隨系統").tag("system")
                }
            }
            
            Section("訓練設定") {
                Stepper("預設休息時間: \(settings.defaultRestTime) 秒", value: $settings.defaultRestTime, in: 30...300, step: 15)
                
                Toggle("自動開始休息計時", isOn: $settings.enableAutoRestTimer)
                
                Toggle("震動回饋", isOn: $settings.enableHapticFeedback)
            }
            
            Section("進階設定") {
                Picker("1RM 計算公式", selection: $settings.oneRMFormula) {
                    Text("Epley").tag("epley")
                    Text("Brzycki").tag("brzycki")
                    Text("Lander").tag("lander")
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
                    showResetAlert = true
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("偏好設定")
        .navigationBarTitleDisplayMode(.inline)
        .alert("重置設定", isPresented: $showResetAlert) {
            Button("取消", role: .cancel) { }
            Button("重置", role: .destructive) {
                settings.resetToDefaults()
            }
        } message: {
            Text("確定要將所有設定恢復為預設值嗎？")
        }
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

