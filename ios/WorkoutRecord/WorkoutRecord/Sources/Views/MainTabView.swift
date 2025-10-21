import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @StateObject private var workoutViewModel = WorkoutViewModel()
    @StateObject private var appSettings = AppSettings.shared
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Dashboard/Home
            DashboardView()
                .tabItem {
                    Label("首頁", systemImage: "house.fill")
                }
                .tag(0)
            
            // Tab 2: Workout
            WorkoutView(viewModel: workoutViewModel)
                .tabItem {
                    Label("訓練", systemImage: "figure.strengthtraining.traditional")
                }
                .tag(1)
            
            // Tab 3: Stats/Analytics
            StatsView()
                .tabItem {
                    Label("數據", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(2)
            
            // Tab 4: History
            HistoryView()
                .tabItem {
                    Label("歷史", systemImage: "calendar")
                }
                .tag(3)
            
            // Tab 5: Settings
            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .accentColor(.blue)
        .preferredColorScheme(appSettings.colorScheme)
        .onReceive(NotificationCenter.default.publisher(for: .startWorkoutFromTemplate)) { notification in
            if let template = notification.userInfo?["template"] as? TemplateInfo {
                // Switch to workout tab
                selectedTab = 1
                // Start workout from template
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    workoutViewModel.startWorkoutFromTemplate(template)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToWorkoutTab)) { _ in
            selectedTab = 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToStatsTab)) { _ in
            selectedTab = 2
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToHistoryTab)) { _ in
            selectedTab = 3
        }
    }
}

#Preview {
    MainTabView()
}

