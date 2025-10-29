import SwiftUI
import Foundation
import Combine

/// 進度系統管理器
class ProgressSystemManager: ObservableObject {
    static let shared = ProgressSystemManager()
    
    @Published var weeklyProgress: WeeklyProgress = WeeklyProgress()
    @Published var monthlyProgress: MonthlyProgress = MonthlyProgress()
    @Published var yearlyProgress: YearlyProgress = YearlyProgress()
    @Published var achievements: [Achievement] = []
    @Published var streaks: [Streak] = []
    
    private let workoutRepository = WorkoutRepository()
    private let personalRecordRepository = PersonalRecordRepository()
    
    private init() {
        loadProgressData()
    }
    
    // MARK: - Progress Loading
    
    /// 載入進度數據
    func loadProgressData() {
        Task {
            await loadWeeklyProgress()
            await loadMonthlyProgress()
            await loadYearlyProgress()
            await loadAchievements()
            await loadStreaks()
        }
    }
    
    /// 載入週進度
    private func loadWeeklyProgress() async {
        let calendar = Calendar.current
        let now = Date()
        
        // 獲取本週的開始和結束日期
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let weekEnd = calendar.dateInterval(of: .weekOfYear, for: now)?.end else {
            return
        }
        
        do {
            let workouts = try workoutRepository.getAllWorkouts()
            
            let totalVolume = workouts.reduce(0) { $0 + $1.totalVolume }
            let totalSets = workouts.reduce(0) { $0 + $1.totalSets }
            let totalDuration = workouts.reduce(0) { $0 + ($1.duration ?? 0) }
            let workoutCount = workouts.count
            
            await MainActor.run {
                weeklyProgress = WeeklyProgress(
                    weekStart: weekStart,
                    weekEnd: weekEnd,
                    totalVolume: totalVolume,
                    totalSets: totalSets,
                    totalDuration: totalDuration,
                    workoutCount: workoutCount,
                    goalWorkouts: 4, // 預設目標
                    goalVolume: 2000, // 預設目標
                    personalRecords: []
                )
            }
        } catch {
            print("❌ 載入週進度失敗: \(error.localizedDescription)")
        }
    }
    
    /// 載入月進度
    private func loadMonthlyProgress() async {
        let calendar = Calendar.current
        let now = Date()
        
        // 獲取本月的開始和結束日期
        guard let monthStart = calendar.dateInterval(of: .month, for: now)?.start,
              let monthEnd = calendar.dateInterval(of: .month, for: now)?.end else {
            return
        }
        
        do {
            let workouts = try workoutRepository.getAllWorkouts()
            
            let totalVolume = workouts.reduce(0) { $0 + $1.totalVolume }
            let totalSets = workouts.reduce(0) { $0 + $1.totalSets }
            let totalDuration = workouts.reduce(0) { $0 + ($1.duration ?? 0) }
            let workoutCount = workouts.count
            
            // 計算平均每週數據
            let weeksInMonth = calendar.dateComponents([.weekOfMonth], from: monthStart, to: monthEnd).weekOfMonth ?? 4
            let avgWeeklyVolume = totalVolume / Double(weeksInMonth)
            let avgWeeklyWorkouts = Double(workoutCount) / Double(weeksInMonth)
            
            await MainActor.run {
                monthlyProgress = MonthlyProgress(
                    monthStart: monthStart,
                    monthEnd: monthEnd,
                    totalVolume: totalVolume,
                    totalSets: totalSets,
                    totalDuration: totalDuration,
                    workoutCount: workoutCount,
                    avgWeeklyVolume: avgWeeklyVolume,
                    avgWeeklyWorkouts: avgWeeklyWorkouts,
                    goalWorkouts: 16, // 預設目標
                    goalVolume: 8000, // 預設目標
                    personalRecords: []
                )
            }
        } catch {
            print("❌ 載入月進度失敗: \(error.localizedDescription)")
        }
    }
    
    /// 載入年進度
    private func loadYearlyProgress() async {
        let calendar = Calendar.current
        let now = Date()
        
        // 獲取本年的開始和結束日期
        guard let yearStart = calendar.dateInterval(of: .year, for: now)?.start,
              let yearEnd = calendar.dateInterval(of: .year, for: now)?.end else {
            return
        }
        
        do {
            let workouts = try workoutRepository.getAllWorkouts()
            
            let totalVolume = workouts.reduce(0) { $0 + $1.totalVolume }
            let totalSets = workouts.reduce(0) { $0 + $1.totalSets }
            let totalDuration = workouts.reduce(0) { $0 + ($1.duration ?? 0) }
            let workoutCount = workouts.count
            
            // 計算平均每月數據
            let monthsInYear = 12
            let avgMonthlyVolume = totalVolume / Double(monthsInYear)
            let avgMonthlyWorkouts = Double(workoutCount) / Double(monthsInYear)
            
            await MainActor.run {
                yearlyProgress = YearlyProgress(
                    yearStart: yearStart,
                    yearEnd: yearEnd,
                    totalVolume: totalVolume,
                    totalSets: totalSets,
                    totalDuration: totalDuration,
                    workoutCount: workoutCount,
                    avgMonthlyVolume: avgMonthlyVolume,
                    avgMonthlyWorkouts: avgMonthlyWorkouts,
                    goalWorkouts: 200, // 預設目標
                    goalVolume: 100000, // 預設目標
                    personalRecords: []
                )
            }
        } catch {
            print("❌ 載入年進度失敗: \(error.localizedDescription)")
        }
    }
    
    /// 載入成就
    private func loadAchievements() async {
        // 模擬成就數據
        let mockAchievements = [
            Achievement(
                id: "beginner",
                title: "初學者",
                description: "完成第一次訓練",
                icon: "figure.strengthtraining.traditional",
                category: .consistency,
                requirement: .workoutCount(1),
                isUnlocked: true,
                unlockedAt: Date().addingTimeInterval(-86400 * 7),
                progress: 1.0
            ),
            Achievement(
                id: "perseverance",
                title: "堅持不懈",
                description: "連續訓練 7 天",
                icon: "flame.fill",
                category: .consistency,
                requirement: .consecutiveDays(7),
                isUnlocked: false,
                unlockedAt: nil,
                progress: 0.43
            ),
            Achievement(
                id: "strength_gain",
                title: "力量提升",
                description: "創造 10 個個人記錄",
                icon: "chart.line.uptrend.xyaxis",
                category: .powerlifting,
                requirement: .workoutCount(10),
                isUnlocked: false,
                unlockedAt: nil,
                progress: 0.5
            ),
            Achievement(
                id: "volume_master",
                title: "容量大師",
                description: "單次訓練容量達到 5000 kg",
                icon: "chart.bar.fill",
                category: .volume,
                requirement: .singleWorkoutVolume(5000),
                isUnlocked: false,
                unlockedAt: nil,
                progress: 0.64
            )
        ]
        
        await MainActor.run {
            achievements = mockAchievements
        }
    }
    
    /// 載入連續記錄
    private func loadStreaks() async {
        // 模擬連續記錄數據
        let mockStreaks = [
            Streak(
                id: UUID(),
                type: .workout,
                currentCount: 3,
                longestCount: 7,
                startDate: Date().addingTimeInterval(-86400 * 3),
                lastActivityDate: Date().addingTimeInterval(-86400),
                isActive: true
            ),
            Streak(
                id: UUID(),
                type: .personalRecord,
                currentCount: 2,
                longestCount: 5,
                startDate: Date().addingTimeInterval(-86400 * 2),
                lastActivityDate: Date().addingTimeInterval(-86400),
                isActive: true
            )
        ]
        
        await MainActor.run {
            streaks = mockStreaks
        }
    }
    
    // MARK: - Progress Calculation
    
    /// 計算進度百分比
    func calculateProgressPercentage(current: Double, goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return min(current / goal, 1.0)
    }
    
    /// 獲取進度狀態
    func getProgressStatus(current: Double, goal: Double) -> ProgressStatus {
        let percentage = calculateProgressPercentage(current: current, goal: goal)
        
        switch percentage {
        case 0..<0.25:
            return .behind
        case 0.25..<0.5:
            return .slow
        case 0.5..<0.75:
            return .onTrack
        case 0.75..<1.0:
            return .ahead
        case 1.0...:
            return .completed
        default:
            return .behind
        }
    }
    
    /// 獲取進度建議
    func getProgressAdvice(for progress: WeeklyProgress) -> String {
        let workoutProgress = calculateProgressPercentage(current: Double(progress.workoutCount), goal: Double(progress.goalWorkouts))
        let volumeProgress = calculateProgressPercentage(current: progress.totalVolume, goal: Double(progress.goalVolume))
        
        if workoutProgress < 0.5 {
            return "建議增加訓練頻率，每週至少訓練 3 次"
        } else if volumeProgress < 0.5 {
            return "建議增加訓練強度或組數"
        } else if workoutProgress >= 1.0 && volumeProgress >= 1.0 {
            return "表現優秀！可以考慮增加新的挑戰"
        } else {
            return "保持目前的訓練節奏，繼續努力！"
        }
    }
}

// MARK: - Data Models

struct WeeklyProgress {
    let weekStart: Date
    let weekEnd: Date
    let totalVolume: Double
    let totalSets: Int
    let totalDuration: Int
    let workoutCount: Int
    let goalWorkouts: Int
    let goalVolume: Double
    let personalRecords: [PersonalRecord]
    
    init(weekStart: Date = Date(), weekEnd: Date = Date(), totalVolume: Double = 0, totalSets: Int = 0, totalDuration: Int = 0, workoutCount: Int = 0, goalWorkouts: Int = 4, goalVolume: Double = 2000, personalRecords: [PersonalRecord] = []) {
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.totalVolume = totalVolume
        self.totalSets = totalSets
        self.totalDuration = totalDuration
        self.workoutCount = workoutCount
        self.goalWorkouts = goalWorkouts
        self.goalVolume = goalVolume
        self.personalRecords = personalRecords
    }
}

struct MonthlyProgress {
    let monthStart: Date
    let monthEnd: Date
    let totalVolume: Double
    let totalSets: Int
    let totalDuration: Int
    let workoutCount: Int
    let avgWeeklyVolume: Double
    let avgWeeklyWorkouts: Double
    let goalWorkouts: Int
    let goalVolume: Double
    let personalRecords: [PersonalRecord]
    
    init(monthStart: Date = Date(), monthEnd: Date = Date(), totalVolume: Double = 0, totalSets: Int = 0, totalDuration: Int = 0, workoutCount: Int = 0, avgWeeklyVolume: Double = 0, avgWeeklyWorkouts: Double = 0, goalWorkouts: Int = 16, goalVolume: Double = 8000, personalRecords: [PersonalRecord] = []) {
        self.monthStart = monthStart
        self.monthEnd = monthEnd
        self.totalVolume = totalVolume
        self.totalSets = totalSets
        self.totalDuration = totalDuration
        self.workoutCount = workoutCount
        self.avgWeeklyVolume = avgWeeklyVolume
        self.avgWeeklyWorkouts = avgWeeklyWorkouts
        self.goalWorkouts = goalWorkouts
        self.goalVolume = goalVolume
        self.personalRecords = personalRecords
    }
}

struct YearlyProgress {
    let yearStart: Date
    let yearEnd: Date
    let totalVolume: Double
    let totalSets: Int
    let totalDuration: Int
    let workoutCount: Int
    let avgMonthlyVolume: Double
    let avgMonthlyWorkouts: Double
    let goalWorkouts: Int
    let goalVolume: Double
    let personalRecords: [PersonalRecord]
    
    init(yearStart: Date = Date(), yearEnd: Date = Date(), totalVolume: Double = 0, totalSets: Int = 0, totalDuration: Int = 0, workoutCount: Int = 0, avgMonthlyVolume: Double = 0, avgMonthlyWorkouts: Double = 0, goalWorkouts: Int = 200, goalVolume: Double = 100000, personalRecords: [PersonalRecord] = []) {
        self.yearStart = yearStart
        self.yearEnd = yearEnd
        self.totalVolume = totalVolume
        self.totalSets = totalSets
        self.totalDuration = totalDuration
        self.workoutCount = workoutCount
        self.avgMonthlyVolume = avgMonthlyVolume
        self.avgMonthlyWorkouts = avgMonthlyWorkouts
        self.goalWorkouts = goalWorkouts
        self.goalVolume = goalVolume
        self.personalRecords = personalRecords
    }
}

// Achievement 定義已移至 Models/Achievement.swift

struct Streak: Identifiable {
    let id: UUID
    let type: StreakType
    let currentCount: Int
    let longestCount: Int
    let startDate: Date
    let lastActivityDate: Date
    let isActive: Bool
}

// AchievementCategory 定義已移至 Models/Achievement.swift

enum StreakType: String, CaseIterable {
    case workout = "workout"
    case personalRecord = "personalRecord"
    
    var displayName: String {
        switch self {
        case .workout: return "訓練"
        case .personalRecord: return "個人記錄"
        }
    }
}

enum ProgressStatus: String, CaseIterable {
    case behind = "behind"
    case slow = "slow"
    case onTrack = "onTrack"
    case ahead = "ahead"
    case completed = "completed"
    
    var displayName: String {
        switch self {
        case .behind: return "落後"
        case .slow: return "緩慢"
        case .onTrack: return "正常"
        case .ahead: return "超前"
        case .completed: return "完成"
        }
    }
    
    var color: Color {
        switch self {
        case .behind: return .red
        case .slow: return .orange
        case .onTrack: return .blue
        case .ahead: return .green
        case .completed: return .purple
        }
    }
}

// MARK: - Progress View

struct ProgressStatsView: View {
    @StateObject private var progressManager = ProgressSystemManager.shared
    @State private var selectedTab: ProgressTab = .weekly
    
    enum ProgressTab: String, CaseIterable {
        case weekly = "週"
        case monthly = "月"
        case yearly = "年"
        case achievements = "成就"
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Tab Picker
                Picker("進度類型", selection: $selectedTab) {
                    ForEach(ProgressTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content
                ScrollView {
                    switch selectedTab {
                    case .weekly:
                        WeeklyProgressView(progress: progressManager.weeklyProgress)
                    case .monthly:
                        MonthlyProgressView(progress: progressManager.monthlyProgress)
                    case .yearly:
                        YearlyProgressView(progress: progressManager.yearlyProgress)
                    case .achievements:
                        AchievementsView()
                    }
                }
            }
            .navigationTitle("進度")
            .onAppear {
                progressManager.loadProgressData()
            }
        }
    }
}

// MARK: - Supporting Views

struct WeeklyProgressView: View {
    let progress: WeeklyProgress
    @StateObject private var progressManager = ProgressSystemManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // 進度卡片
            ProgressCard(
                title: "本週進度",
                subtitle: "\(progress.weekStart.formatted(date: .abbreviated, time: .omitted)) - \(progress.weekEnd.formatted(date: .abbreviated, time: .omitted))",
                progress: progressManager.calculateProgressPercentage(current: Double(progress.workoutCount), goal: Double(progress.goalWorkouts)),
                current: "\(progress.workoutCount)",
                goal: "\(progress.goalWorkouts)",
                unit: "次訓練"
            )
            
            // 統計數據
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                StatCard(title: "總容量", value: "\(Int(progress.totalVolume)) kg", icon: "chart.bar.fill", color: .blue)
                StatCard(title: "總組數", value: "\(progress.totalSets)", icon: "list.number", color: .green)
                StatCard(title: "總時長", value: "\(progress.totalDuration) 分鐘", icon: "clock.fill", color: .orange)
                StatCard(title: "個人記錄", value: "\(progress.personalRecords.count)", icon: "trophy.fill", color: .purple)
            }
            
            // 建議
            AdviceCard(advice: progressManager.getProgressAdvice(for: progress))
        }
        .padding()
    }
}

struct MonthlyProgressView: View {
    let progress: MonthlyProgress
    @StateObject private var progressManager = ProgressSystemManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // 進度卡片
            ProgressCard(
                title: "本月進度",
                subtitle: "\(progress.monthStart.formatted(.dateTime.month(.wide).year()))",
                progress: progressManager.calculateProgressPercentage(current: Double(progress.workoutCount), goal: Double(progress.goalWorkouts)),
                current: "\(progress.workoutCount)",
                goal: "\(progress.goalWorkouts)",
                unit: "次訓練"
            )
            
            // 平均數據
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                StatCard(title: "平均週容量", value: "\(Int(progress.avgWeeklyVolume)) kg", icon: "chart.bar.fill", color: .blue)
                StatCard(title: "平均週訓練", value: String(format: "%.1f 次", progress.avgWeeklyWorkouts), icon: "calendar", color: .green)
                StatCard(title: "總容量", value: "\(Int(progress.totalVolume)) kg", icon: "chart.bar.fill", color: .orange)
                StatCard(title: "總時長", value: "\(progress.totalDuration) 分鐘", icon: "clock.fill", color: .purple)
            }
        }
        .padding()
    }
}

struct YearlyProgressView: View {
    let progress: YearlyProgress
    @StateObject private var progressManager = ProgressSystemManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // 進度卡片
            ProgressCard(
                title: "今年進度",
                subtitle: "\(progress.yearStart.formatted(.dateTime.year()))",
                progress: progressManager.calculateProgressPercentage(current: Double(progress.workoutCount), goal: Double(progress.goalWorkouts)),
                current: "\(progress.workoutCount)",
                goal: "\(progress.goalWorkouts)",
                unit: "次訓練"
            )
            
            // 平均數據
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                StatCard(title: "平均月容量", value: "\(Int(progress.avgMonthlyVolume)) kg", icon: "chart.bar.fill", color: .blue)
                StatCard(title: "平均月訓練", value: String(format: "%.1f 次", progress.avgMonthlyWorkouts), icon: "calendar", color: .green)
                StatCard(title: "總容量", value: "\(Int(progress.totalVolume)) kg", icon: "chart.bar.fill", color: .orange)
                StatCard(title: "總時長", value: "\(progress.totalDuration) 分鐘", icon: "clock.fill", color: .purple)
            }
        }
        .padding()
    }
}

// AchievementsView 和 AchievementCard 定義已移至 Views/Achievements/AchievementsView.swift

// MARK: - Supporting Components

struct ProgressCard: View {
    let title: String
    let subtitle: String
    let progress: Double
    let current: String
    let goal: String
    let unit: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
            
            HStack {
                Text("\(current) / \(goal) \(unit)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// StatCard 定義已移至 Views/Components/StatCardView.swift

// AchievementCard 定義已移至 Views/Achievements/AchievementsView.swift

struct AdviceCard: View {
    let advice: String
    
    var body: some View {
        HStack {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.yellow)
            
            Text(advice)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    SwiftUI.ProgressView()
}
