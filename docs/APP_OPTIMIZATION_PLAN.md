# WorkoutRecord App 優化計畫

## 📋 專案掃描結果

### 當前狀態總覽
- ✅ **核心功能完整**：訓練記錄、體重記錄、數據分析、歷史查詢
- ✅ **架構清晰**：MVVM 架構，CoreData 持久化
- ✅ **UI 統一**：SwiftUI 實作，已有基本設計系統
- ⚠️ **待優化項目**：元件化、首次啟動體驗、雲端同步、動畫效果

---

## 1️⃣ 元件化分析與建議

### 🔍 發現的可重複使用元件

#### 1.1 **統計卡片元件** (已重複出現 3+ 次)
**當前狀況：**
- `DashboardView.swift` 中的 `StatCard`
- `StatsView.swift` 中的 `WorkoutStatCard`
- `BodyWeightView.swift` 中的 `BodyWeightStatItem`

**建議：** 統一為通用 `StatCardView` 元件

```swift
// 新增: Views/Components/StatCardView.swift
struct StatCardView: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    var trend: TrendDirection? = nil
    
    enum TrendDirection {
        case up, down, neutral
    }
}
```

#### 1.2 **空狀態視圖** (已重複出現 4+ 次)
**當前狀況：**
- `EmptyHistoryView`
- `EmptyBodyWeightView`
- `EmptyWorkoutStatsView`
- 其他空狀態散落在各處

**建議：** 創建通用 `EmptyStateView` 元件

```swift
// 新增: Views/Components/EmptyStateView.swift
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionButton: ActionButton? = nil
    
    struct ActionButton {
        let title: String
        let action: () -> Void
    }
}
```

#### 1.3 **訓練卡片** (已重複出現 3+ 次)
**當前狀況：**
- `WorkoutHistoryCard` (HistoryView)
- `RecentWorkoutRow` (DashboardView)
- `WorkoutStatsRow` (StatsView)

**建議：** 統一為 `WorkoutSummaryCard`

```swift
// 新增: Views/Components/WorkoutSummaryCard.swift
struct WorkoutSummaryCard: View {
    let workout: WorkoutSummary
    var style: CardStyle = .full
    
    enum CardStyle {
        case full      // 完整資訊
        case compact   // 精簡版
        case minimal   // 最小化
    }
}
```

#### 1.4 **快速操作按鈕** (已重複)
**當前狀況：**
- `QuickActionButton` (DashboardView)
- `QuickActionLinkButton` (DashboardView)
- 其他按鈕樣式分散

**建議：** 統一按鈕系統

```swift
// 新增: Views/Components/ActionButton.swift
struct ActionButton: View {
    let icon: String
    let title: String
    let color: Color
    var style: ButtonStyle = .filled
    let action: () -> Void
    
    enum ButtonStyle {
        case filled, outlined, plain
    }
}
```

#### 1.5 **篩選晶片** (已重複)
**當前狀況：**
- `FilterChip` (VolumeChartView)
- `FilterButton` (PRView)

**建議：** 統一為 `FilterChipView`

```swift
// 新增: Views/Components/FilterChipView.swift
struct FilterChipView: View {
    let title: String
    let isSelected: Bool
    var color: Color = .blue
    var showIndicator: Bool = true
    let action: () -> Void
}
```

### 📦 建議的 Components 目錄結構

```
Sources/Views/Components/
├── Cards/
│   ├── StatCardView.swift          # 統計卡片
│   ├── WorkoutSummaryCard.swift    # 訓練摘要卡片
│   └── InfoCard.swift              # 通用資訊卡片
├── Buttons/
│   ├── ActionButton.swift          # 快速操作按鈕
│   ├── FilterChipView.swift        # 篩選晶片
│   └── FloatingActionButton.swift  # 浮動按鈕
├── States/
│   ├── EmptyStateView.swift        # 空狀態
│   ├── LoadingView.swift           # 載入狀態
│   └── ErrorView.swift             # 錯誤狀態
├── Inputs/
│   ├── NumberTextField.swift       # 數字輸入
│   └── DateTimePicker.swift        # 日期時間選擇器
└── FlowLayout.swift                # 保留現有
```

---

## 2️⃣ 如何更換 App 圖示

### 步驟說明

#### 方法一：使用 Xcode Assets Catalog（推薦）

1. **準備圖示檔案**
   - 需要準備不同尺寸的圖示（建議從 1024x1024 開始）
   - 格式：PNG (無透明背景)
   - 可使用線上工具生成：
     - https://www.appicon.co/
     - https://appicon.build/

2. **在 Xcode 中操作**
   ```
   1. 打開 WorkoutRecord.xcodeproj
   2. 在左側導航欄找到 Assets.xcassets
   3. 點擊 AppIcon
   4. 將各尺寸圖示拖放到對應位置
   ```

3. **需要的尺寸**
   - iPhone App: 60x60 (@2x, @3x), 76x76, 83.5x83.5, 1024x1024
   - App Store: 1024x1024 (必須)

#### 方法二：快速替換（開發測試用）

1. **直接替換檔案**
   ```bash
   cd /Users/mike/Documents/self/workout-record/ios/WorkoutRecord/WorkoutRecord/Assets.xcassets/AppIcon.appiconset
   ```

2. **放入你的圖示檔案**，並確保檔名與 `Contents.json` 中的定義一致

3. **清理並重新建置**
   ```
   Product > Clean Build Folder (⇧⌘K)
   Product > Build (⌘B)
   ```

### 設計建議
- **風格**：簡潔、識別度高
- **配色**：與 App 主題一致（藍色系）
- **圖案**：啞鈴、肌肉線條、或進度圖表元素
- **文字**：避免放文字，純圖示為佳

---

## 3️⃣ Apple 開發者帳號與 Xcode 設定

### 已通過開發者帳號後的設定步驟

#### Step 1: 登入 Apple Developer Account
```
Xcode > Settings (⌘,) > Accounts
點擊 "+" > Apple ID
輸入你的 Apple Developer Account
```

#### Step 2: 設定專案簽名
```
1. 選擇專案 "WorkoutRecord" (藍色圖示)
2. 選擇 Target "WorkoutRecord"
3. 切換到 "Signing & Capabilities" 標籤
4. 勾選 "Automatically manage signing"
5. Team: 選擇你的開發者帳號
6. Bundle Identifier: 確認唯一性 (例如: com.yourname.workoutrecord)
```

#### Step 3: 設定 App ID 與 Capabilities

**需要的 Capabilities：**
- [x] Sign in with Apple（如果要做 Apple 登入）
- [ ] Push Notifications（通知功能）
- [ ] iCloud（雲端同步）
- [ ] HealthKit（健康數據整合，可選）

**在 Xcode 中新增：**
```
Signing & Capabilities > "+ Capability" > 選擇需要的功能
```

#### Step 4: 真機測試設定
```
1. 連接 iPhone
2. iPhone 上信任電腦
3. 設定 > 隱私權與安全性 > 開發者模式 > 開啟
4. 重新啟動 iPhone
5. Xcode 選擇你的裝置
6. 按下 Run (⌘R)
```

#### Step 5: 準備上架（TestFlight/App Store）

**App Store Connect 設定：**
```
1. 登入 https://appstoreconnect.apple.com
2. 我的 App > "+" > 新增 App
3. 填寫基本資訊：
   - 平台: iOS
   - 名稱: WorkoutRecord (或你的 App 名稱)
   - 主要語言: 繁體中文
   - Bundle ID: 選擇剛才建立的
   - SKU: 任意唯一識別碼 (例如: workoutrecord-001)
```

**Archive 與上傳：**
```
1. Xcode: Product > Archive
2. 等待編譯完成
3. Window > Organizer
4. 選擇剛才的 Archive
5. 點擊 "Distribute App"
6. 選擇 "App Store Connect"
7. 上傳
```

---

## 4️⃣ 後續優化計畫

### 4-1. 移除個人設定中無用的功能

**需要移除的功能：**
```swift
// SettingsView.swift Line 75-87
Section("數據管理") {
    Button { } label: { Label("匯出數據", ...) }  // ❌ 移除
    Button { } label: { Label("匯入數據", ...) }  // ❌ 移除
}
```

**保留的功能：**
- ✅ 個人資料
- ✅ 目標設定
- ✅ 動作庫管理
- ✅ 訓練模板
- ✅ 偏好設定
- ✅ 通知設定

---

### 4-2. 移除未完成的功能

**掃描結果 - 需要處理的 TODO：**

1. **SettingsView.swift**
   - Line 68-71: 通知設定頁面空白
   - Line 99-102: 使用教學頁面空白
   - Line 104-108: 關於我們頁面空白

2. **HistoryView.swift**
   - Line 36-39: 篩選功能未實作

3. **WorkoutView.swift**
   - Line 49: 休息時間應從設定取得

**處理方式：**
- 選項 1：完成這些功能（建議優先完成）
- 選項 2：暫時隱藏，標記為「即將推出」
- 選項 3：完全移除入口

**建議：** 保留「使用教學」和「關於我們」，但導向實際內容；移除篩選功能入口（或改為灰色不可點擊）

---

### 4-3. 首次啟動強制輸入基本資訊

**實作方案：**

```swift
// 新增: Sources/Models/OnboardingState.swift
class OnboardingState: ObservableObject {
    @AppStorage("hasCompletedOnboarding") var hasCompleted = false
    @Published var currentStep = 0
}

// 新增: Sources/Views/Onboarding/OnboardingView.swift
struct OnboardingView: View {
    @ObservedObject var state: OnboardingState
    @State private var weight: String = ""
    @State private var gender: String = "不指定"
    @State private var age: String = ""
    @State private var targetWeight: String = ""
    
    var body: some View {
        TabView(selection: $state.currentStep) {
            WelcomeStep()
                .tag(0)
            
            BasicInfoStep(
                weight: $weight,
                gender: $gender,
                age: $age
            )
            .tag(1)
            
            GoalStep(targetWeight: $targetWeight)
                .tag(2)
            
            CompletionStep()
                .tag(3)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }
}

// 修改: WorkoutRecordApp.swift
@main
struct WorkoutRecordApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var onboardingState = OnboardingState()
    
    var body: some Scene {
        WindowGroup {
            if onboardingState.hasCompleted {
                MainTabView()
                    .environmentObject(appState)
            } else {
                OnboardingView(state: onboardingState)
            }
        }
    }
}
```

**需要收集的資訊：**
1. 歡迎頁（說明 App 功能）
2. 基本資訊：當前體重、性別、年齡
3. 目標設定：理想體重、每週訓練次數
4. 完成頁（可開始使用）

---

### 4-4. 雲端儲存方案分析

#### 方案比較表

| 方案 | 費用 | 優點 | 缺點 | 推薦度 |
|------|------|------|------|--------|
| **iCloud (CloudKit)** | 免費額度大 | • Apple 原生整合<br>• 免費：1GB 儲存 + 傳輸<br>• 自動處理 Apple ID<br>• 隱私保護好 | • 僅限 Apple 生態<br>• 學習曲線較陡 | ⭐⭐⭐⭐⭐ |
| **Firebase** | $25/月起 | • 功能完整<br>• 文檔豐富<br>• 即時同步 | • Google 服務<br>• 免費額度小<br>• 成本較高 | ⭐⭐⭐ |
| **Supabase** | 免費/$25/月 | • 開源<br>• PostgreSQL<br>• 免費額度可用 | • 新專案<br>• 生態較小 | ⭐⭐⭐⭐ |
| **自建後端** | VPS $5-20/月 | • 完全掌控<br>• 成本可控 | • 需自己維護<br>• 開發時間長 | ⭐⭐⭐ |

#### 💡 推薦方案：**iCloud (CloudKit)**

**理由：**
1. **成本最低**：免費額度充足（每用戶 1GB，對健身數據綽綽有餘）
2. **原生整合**：SwiftUI + CloudKit 開發體驗佳
3. **自動處理**：Apple ID 登入、裝置同步自動處理
4. **隱私保護**：符合 Apple 生態系用戶期待

**預估成本：**
```
用戶數 < 10,000: 完全免費
用戶數 10,000-100,000: 約 $0-50/月
```

**實作複雜度：** 中等（約 1-2 週開發時間）

#### 備選方案：**Supabase**（如需跨平台）

**適用情境：** 未來要做 Android 版
**費用：** 免費版 500MB 資料庫 + 2GB 儲存
**超過後：** $25/月

---

### 4-5. 新手教學設計

#### 教學方式建議

**方案 A：引導式教學（Onboarding + Inline Tips）**
```swift
// 特性：
- 首次開啟時的完整引導流程
- 各頁面首次進入時的浮層提示
- 可重新觀看教學（設定中）
```

**方案 B：互動式教學頁面**
```swift
// 特性：
- 獨立的「使用教學」頁面
- 圖文並茂的功能說明
- 短影片示範（可選）
```

**推薦：混合方案**
1. **首次啟動**：Onboarding 流程（基本資訊 + 核心功能介紹）
2. **Inline Tips**：各功能首次使用時的提示氣泡
3. **教學中心**：設定中的完整教學文件

#### 教學內容規劃

```
第一步：開始訓練
├─ 如何新增動作
├─ 如何記錄組數
└─ 如何完成訓練

第二步：查看數據
├─ 理解容量趨勢圖
├─ 查看個人記錄 (PR)
└─ 追蹤體重變化

第三步：進階功能
├─ 使用訓練模板
├─ 自定義動作
└─ 設定訓練目標
```

---

### 4-6. 本地 30 天數據保留機制

#### 實作方案

```swift
// 新增: Sources/Services/DataRetentionService.swift
class DataRetentionService {
    static let shared = DataRetentionService()
    private let coreData = CoreDataStack.shared
    
    /// 本地資料保留天數
    private let localRetentionDays = 30
    
    /// 清理超過 30 天的本地訓練數據
    func cleanOldLocalData() async throws {
        let cutoffDate = Calendar.current.date(
            byAdding: .day, 
            value: -localRetentionDays, 
            to: Date()
        )!
        
        // 1. 標記需要雲端備份的數據（如果有同步）
        try await backupToCloudIfNeeded(before: cutoffDate)
        
        // 2. 刪除本地舊數據
        try await deleteLocalData(before: cutoffDate)
    }
    
    /// 檢查是否需要清理（每週執行一次）
    func scheduleCleanup() {
        let lastCleanup = UserDefaults.standard.object(forKey: "LastDataCleanup") as? Date
        let shouldClean = lastCleanup == nil || 
                         Date().timeIntervalSince(lastCleanup!) > 7 * 24 * 3600
        
        if shouldClean {
            Task {
                try? await cleanOldLocalData()
                UserDefaults.standard.set(Date(), forKey: "LastDataCleanup")
            }
        }
    }
}

// 在 App 啟動時執行
// WorkoutRecordApp.swift
.onAppear {
    DataRetentionService.shared.scheduleCleanup()
}
```

#### 付費會員雲端完整保存策略

```
免費用戶：
├─ 本地保留 30 天數據
├─ 可手動匯出備份
└─ 統計數據仍保留（不含詳細組數）

付費會員：
├─ 雲端完整保存所有數據
├─ 多裝置同步
├─ 進階數據分析
└─ 無限歷史記錄查詢
```

---

### 4-7. 使用者行為分析

#### 推薦工具：**TelemetryDeck**（隱私友善）

**特點：**
- ✅ 符合 Apple 隱私政策
- ✅ 不收集個人資訊
- ✅ 開源可信任
- ✅ 免費額度：10,000 事件/月

**需要追蹤的行為：**

```swift
// 核心行為
- app_launched               // App 啟動
- workout_started            // 開始訓練
- workout_completed          // 完成訓練
- exercise_added             // 新增動作
- body_weight_logged         // 記錄體重

// 功能使用
- chart_viewed               // 查看圖表
- template_used              // 使用模板
- pr_viewed                  // 查看 PR
- custom_exercise_created    // 建立自訂動作

// 付費意願指標
- premium_feature_attempted  // 嘗試使用付費功能
- stats_tab_visited          // 訪問數據分析頁面
- advanced_chart_viewed      // 查看進階圖表
```

#### 實作範例

```swift
// 新增: Sources/Services/AnalyticsService.swift
import TelemetryClient

class AnalyticsService {
    static let shared = AnalyticsService()
    
    private let telemetry = TelemetryManager(configuration: .init(
        appID: "YOUR-APP-ID"
    ))
    
    func track(_ event: AnalyticsEvent) {
        telemetry.send(event.rawValue)
    }
}

enum AnalyticsEvent: String {
    case workoutStarted = "workout_started"
    case workoutCompleted = "workout_completed"
    case premiumFeatureAttempted = "premium_feature_attempted"
    // ...
}

// 使用範例
AnalyticsService.shared.track(.workoutCompleted)
```

---

### 4-8. 經典三項 1RM 趨勢圖 + 成就系統

#### 功能設計

**經典三項：**
1. 深蹲 (Squat)
2. 臥推 (Bench Press)
3. 硬舉 (Deadlift)

#### UI 設計

```swift
// 新增: Sources/Views/Stats/PowerliftingStatsView.swift
struct PowerliftingStatsView: View {
    @StateObject private var viewModel = PowerliftingViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. 三項總和卡片
                totalCard
                
                // 2. 單項趨勢圖切換
                Picker("動作", selection: $viewModel.selectedLift) {
                    Text("深蹲").tag(PowerLift.squat)
                    Text("臥推").tag(PowerLift.benchPress)
                    Text("硬舉").tag(PowerLift.deadlift)
                }
                .pickerStyle(.segmented)
                
                // 3. 1RM 趨勢圖
                OneRMTrendChart(data: viewModel.chartData)
                
                // 4. PR 記錄輸入（可選）
                prInputSection
                
                // 5. 歷史記錄
                prHistoryList
            }
        }
    }
}
```

#### 成就系統設計

**新增頁面：AchievementsView**

```swift
// 新增: Sources/Views/Achievements/AchievementsView.swift
struct AchievementsView: View {
    @StateObject private var viewModel = AchievementsViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 成就進度總覽
                achievementProgress
                
                // 分類
                ForEach(AchievementCategory.allCases) { category in
                    AchievementSection(
                        category: category,
                        achievements: viewModel.achievements(for: category)
                    )
                }
            }
        }
    }
}
```

**成就分類：**

```swift
enum AchievementCategory: String, CaseIterable {
    case powerlifting = "力量成就"      // 重量里程碑
    case volume = "容量成就"            // 訓練量目標
    case consistency = "堅持成就"       // 連續訓練
    case special = "特殊成就"           // 特殊條件
}

// 成就範例
let achievements = [
    // 力量成就
    Achievement(
        id: "squat_100kg",
        title: "深蹲破百",
        description: "深蹲 1RM 達到 100kg",
        icon: "💪",
        category: .powerlifting,
        requirement: .oneRM(.squat, 100)
    ),
    
    Achievement(
        id: "total_300kg",
        title: "三項 300 俱樂部",
        description: "三項總和達到 300kg",
        icon: "🏆",
        category: .powerlifting,
        requirement: .totalLifts(300)
    ),
    
    // 容量成就
    Achievement(
        id: "volume_10000kg",
        title: "萬公斤俱樂部",
        description: "單次訓練容量達 10,000kg",
        icon: "📊",
        category: .volume,
        requirement: .singleWorkoutVolume(10000)
    ),
    
    // 堅持成就
    Achievement(
        id: "streak_30",
        title: "月度勇士",
        description: "連續 30 天訓練",
        icon: "🔥",
        category: .consistency,
        requirement: .consecutiveDays(30)
    ),
    
    // 特殊成就
    Achievement(
        id: "first_workout",
        title: "新的開始",
        description: "完成第一次訓練",
        icon: "🌟",
        category: .special,
        requirement: .workoutCount(1)
    )
]
```

#### 分享功能

```swift
// 成就解鎖後可分享
struct AchievementShareCard: View {
    let achievement: Achievement
    
    var body: some View {
        VStack {
            // 設計精美的分享卡片
            // 可包含：成就圖示、名稱、達成日期、App Logo
        }
        .background(
            LinearGradient(...)
        )
    }
}

// 分享按鈕
Button("分享成就") {
    shareAchievement()
}

func shareAchievement() {
    let image = AchievementShareCard(achievement: achievement)
        .snapshot() // 轉為圖片
    
    let activityVC = UIActivityViewController(
        activityItems: [image],
        applicationActivities: nil
    )
    // 呈現分享面板
}
```

---

## 🎨 動畫優化建議

### 建議的動畫效果

```swift
// 1. 頁面轉場動畫
.transition(.asymmetric(
    insertion: .move(edge: .trailing).combined(with: .opacity),
    removal: .move(edge: .leading).combined(with: .opacity)
))

// 2. 卡片出現動畫
ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
    CardView(item: item)
        .transition(.opacity.combined(with: .scale))
        .animation(.spring(response: 0.3, dampingFraction: 0.7)
            .delay(Double(index) * 0.05), value: items)
}

// 3. 數字滾動動畫
Text("\(Int(animatedValue))")
    .contentTransition(.numericText())
    .animation(.spring(), value: animatedValue)

// 4. 按鈕點擊回饋
.scaleEffect(isPressed ? 0.95 : 1.0)
.animation(.spring(response: 0.2), value: isPressed)
```

---

## 📊 優先順序建議

### Phase 1: 基礎優化（1 週）
1. ✅ 元件化重構
2. ✅ 移除無用功能
3. ✅ App 圖示設計與替換

### Phase 2: 首次體驗（1 週）
4. ✅ Onboarding 流程
5. ✅ 新手教學
6. ✅ 基礎動畫優化

### Phase 3: 數據功能（1-2 週）
7. ✅ 經典三項 1RM 趨勢圖
8. ✅ 成就系統
9. ✅ 30 天數據保留機制
10. ✅ 使用者行為分析整合

### Phase 4: 雲端同步（2-3 週）
11. ✅ CloudKit 整合
12. ✅ Apple Sign In
13. ✅ 數據同步機制

---

## 總結

您的 App 目前功能已經相當完整，接下來的優化重點：

1. **立即可做**：元件化、移除無用功能、更換圖示
2. **優先重要**：首次啟動體驗、新手教學
3. **提升價值**：成就系統、進階數據分析
4. **長期規劃**：雲端同步、付費會員功能

建議按照 Phase 1 → Phase 2 → Phase 3 → Phase 4 的順序進行，確保每個階段都能交付可用的版本。

---

**文件建立日期**：2025-10-22
**當前 App 版本**：v0.4.2

