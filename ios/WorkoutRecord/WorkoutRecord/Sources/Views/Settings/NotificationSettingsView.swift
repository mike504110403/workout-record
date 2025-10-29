import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @State private var workoutReminders = true
    @State private var restTimerAlerts = true
    @State private var achievementNotifications = true
    @State private var weeklyReports = false
    @State private var reminderTime = Date()
    @State private var showingPermissionAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("訓練提醒", isOn: $workoutReminders)
                        .onChange(of: workoutReminders) { _, newValue in
                            if newValue {
                                requestNotificationPermission()
                            }
                        }
                    
                    if workoutReminders {
                        DatePicker("提醒時間", selection: $reminderTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.compact)
                    }
                } header: {
                    Text("提醒設定")
                } footer: {
                    Text("設定每日訓練提醒，幫助您保持健身習慣")
                }
                
                Section {
                    Toggle("休息計時器提醒", isOn: $restTimerAlerts)
                    Toggle("成就通知", isOn: $achievementNotifications)
                    Toggle("週報通知", isOn: $weeklyReports)
                } header: {
                    Text("其他通知")
                } footer: {
                    Text("自定義您想要接收的通知類型")
                }
                
                Section {
                    Button("測試通知") {
                        sendTestNotification()
                    }
                    
                    Button("清除所有通知") {
                        clearAllNotifications()
                    }
                    .foregroundColor(.red)
                } header: {
                    Text("通知測試")
                } footer: {
                    Text("測試通知功能或清除所有待發送的通知")
                }
                
                if !isNotificationPermissionGranted() {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("通知權限未開啟")
                                    .font(.headline)
                            }
                            
                            Text("請在設定中開啟通知權限，以接收訓練提醒和成就通知")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button("前往設定") {
                                openAppSettings()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("通知設定")
            .navigationBarTitleDisplayMode(.inline)
            .alert("需要通知權限", isPresented: $showingPermissionAlert) {
                Button("取消", role: .cancel) { }
                Button("前往設定") {
                    openAppSettings()
                }
            } message: {
                Text("請在設定中開啟通知權限，以接收訓練提醒")
            }
            .onAppear {
                loadNotificationSettings()
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                if !granted {
                    showingPermissionAlert = true
                }
            }
        }
    }
    
    private func isNotificationPermissionGranted() -> Bool {
        // 簡化檢查，實際應用中需要異步檢查權限狀態
        return true
    }
    
    private func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "健身記錄"
        content.body = "這是測試通知，通知功能正常運作！"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "test", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ 測試通知失敗: \(error)")
            } else {
                print("✅ 測試通知已發送")
            }
        }
    }
    
    private func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
    
    private func openAppSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    private func loadNotificationSettings() {
        // 從 UserDefaults 載入設定
        workoutReminders = UserDefaults.standard.bool(forKey: "workoutReminders")
        restTimerAlerts = UserDefaults.standard.bool(forKey: "restTimerAlerts")
        achievementNotifications = UserDefaults.standard.bool(forKey: "achievementNotifications")
        weeklyReports = UserDefaults.standard.bool(forKey: "weeklyReports")
        
        if let savedTime = UserDefaults.standard.object(forKey: "reminderTime") as? Date {
            reminderTime = savedTime
        }
    }
    
    private func saveNotificationSettings() {
        UserDefaults.standard.set(workoutReminders, forKey: "workoutReminders")
        UserDefaults.standard.set(restTimerAlerts, forKey: "restTimerAlerts")
        UserDefaults.standard.set(achievementNotifications, forKey: "achievementNotifications")
        UserDefaults.standard.set(weeklyReports, forKey: "weeklyReports")
        UserDefaults.standard.set(reminderTime, forKey: "reminderTime")
    }
}

#Preview {
    NotificationSettingsView()
}
