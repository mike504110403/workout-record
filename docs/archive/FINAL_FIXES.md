# 最終功能修復清單

## 📋 需求確認與修復狀態

### ✅ 需求 1: 完成動作時停止休息計時器
**狀態**: ✅ 已修復

**修復內容**:
- 在 `WorkoutView.swift` 中添加了 `restTimerManager.stop()` 調用
- 當用戶點擊"標記完成"時，會自動停止休息計時器
- 用戶仍可在休息期間添加新組數（按需求）

**代碼位置**: `WorkoutView.swift` Line 214-217

---

### ⏳ 需求 2: 三項頁面顯示系統推估數據
**狀態**: ✅ 已實現（但可能需要數據）

**當前狀態**:
- `PowerliftingView.swift` 已有 `systemEstimatedSection`
- `PowerliftingViewModel.swift` 已有數據加載邏輯
- 會自動從訓練記錄中提取三項數據

**可能的問題**:
如果看不到系統推估數據，原因可能是：
1. 還沒有相關的訓練記錄
2. 訓練記錄中的動作名稱不匹配

**解決方案**:
- 去訓練頁面記錄一些深蹲、臥推、硬舉的訓練
- 系統會自動推估 1RM 並顯示在三項頁面

**代碼位置**: 
- UI: `PowerliftingView.swift` Line 195-233
- ViewModel: `PowerliftingViewModel.swift` Line 125-175

---

### ⚠️ 需求 3: 重量單位切換（容量趨勢/歷史記錄）
**狀態**: ⏳ 部分完成（需要全面檢查）

**已完成**:
- ✅ 訓練記錄時的重量單位切換
- ✅ `AddSetSheet` 顯示正確單位

**需要修復**:
- ❌ 容量趨勢圖表的 Y 軸單位
- ❌ 歷史記錄詳情的重量顯示
- ❌ 三項頁面的重量顯示
- ❌ PR 記錄的重量顯示

**修復方案**:
需要在以下文件中使用 `WeightFormatter`:

1. **容量趨勢圖** (`VolumeChartView.swift` 或相關)
2. **歷史記錄** (`WorkoutDetailView.swift`)
3. **三項頁面** (`PowerliftingView.swift`)
4. **PR 顯示** (相關頁面)

---

### ⚠️ 需求 4: 成就彈窗和通知
**狀態**: ⏳ 部分完成

**已實現**:
- ✅ 成就檢查邏輯 (`AchievementCheckerService`)
- ✅ 成就彈窗 UI (`AchievementUnlockedView`)
- ✅ 在 `MainTabView` 中監聽成就解鎖

**可能的問題**:
1. **成就觸發時機**: 目前只在完成訓練時檢查
2. **手動記錄的檢查**: 三項頁面手動添加記錄時，可能沒有觸發成就檢查
3. **通知紅點**: 需要在 Tab 圖標上顯示紅點

**需要修復**:
- 在三項頁面手動添加記錄時，觸發成就檢查
- 在成就頁面添加紅點提示

---

## 🔧 快速修復指南

### 修復 3: 重量單位切換

#### Step 1: 統一使用 WeightFormatter

在所有顯示重量的地方，使用 `WeightFormatter.shared.format`：

```swift
// 錯誤做法
Text("\(weight) kg")

// 正確做法
Text(WeightFormatter.shared.format(weight))  // 自動根據偏好顯示 kg 或 lb
```

#### Step 2: 需要修改的文件列表

1. **PowerliftingView.swift**
   - Line 67: `Text("kg")` → 使用動態單位
   - Line 81: 重量顯示 → 使用 WeightFormatter
   - Line 206: `Text("推估: \(String(format: "%.1f", pr.oneRepMax)) kg")` → 使用 WeightFormatter

2. **WorkoutDetailView.swift**
   - 所有重量顯示 → 使用 WeightFormatter

3. **VolumeChartView.swift** (如果存在)
   - 圖表 Y 軸標籤 → 使用 WeightFormatter

4. **PR 相關視圖**
   - 所有個人紀錄重量顯示 → 使用 WeightFormatter

---

### 修復 4: 成就彈窗

#### Step 1: 在手動添加記錄時觸發檢查

在 `PowerliftingViewModel.swift` 的 `addManualRecord` 方法中：

```swift
func addManualRecord(weight: Double, reps: Int, date: Date, note: String?) {
    // ... 保存記錄的代碼 ...
    
    // 添加以下代碼：
    // 觸發成就檢查
    AchievementCheckerService.shared.checkForNewAchievements()
}
```

#### Step 2: 添加通知紅點

在 `MainTabView.swift` 中，為"數據" Tab 添加徽章：

```swift
.badge(unreadAchievementsCount)  // 顯示未讀成就數量
```

---

## 📊 測試清單

### 測試 1: 休息計時器
- [ ] 開始訓練
- [ ] 添加一個動作並記錄組數
- [ ] 確認休息計時器在 Header 顯示
- [ ] 點擊"標記完成"
- [ ] 確認計時器停止

### 測試 2: 三項推估
- [ ] 記錄深蹲訓練（例如: 100kg x 5reps）
- [ ] 完成訓練
- [ ] 前往"數據" → "經典三項"
- [ ] 切換到"深蹲"
- [ ] 確認"訓練推估"區域有數據

### 測試 3: 重量單位
- [ ] 前往設定 → 偏好設定
- [ ] 切換重量單位為"磅"
- [ ] 檢查以下頁面的重量顯示：
  - [ ] 訓練記錄頁面
  - [ ] 容量趨勢圖
  - [ ] 歷史記錄詳情
  - [ ] 三項頁面
  - [ ] PR 記錄

### 測試 4: 成就彈窗
- [ ] 在三項頁面手動添加 "臥推 100kg x 1"
- [ ] 確認成就彈窗出現 "臥推破百"
- [ ] 前往數據頁面
- [ ] 確認有紅點提示

---

## 🚀 建議的修復順序

### 優先級 1（影響用戶體驗）
1. ✅ 休息計時器停止（已修復）
2. ⏳ 重量單位切換（需要修復）

### 優先級 2（功能完整性）
3. ⏳ 三項推估數據（已實現，可能需要數據）
4. ⏳ 成就彈窗和紅點（部分完成）

---

## 💡 下一步行動

### 立即可做
1. 測試休息計時器功能
2. 記錄一些訓練數據，測試三項推估
3. 測試重量單位切換

### 需要代碼修復
1. 全面修復重量單位顯示（需要修改多個文件）
2. 添加手動記錄時的成就檢查
3. 添加通知紅點

### 時間估算
- 重量單位修復：30-60 分鐘
- 成就系統完善：15-30 分鐘
- 測試和驗證：30 分鐘

**總計：1.5-2 小時**

---

## ✅ 總結

**當前狀態**:
- ✅ 需求 1: 已修復
- 🟡 需求 2: 已實現（需要數據測試）
- ⚠️ 需求 3: 需要全面修復
- 🟡 需求 4: 部分完成

**建議**:
1. 先測試現有功能（需求 1 和 2）
2. 確認問題後，再修復重量單位（需求 3）
3. 最後完善成就系統（需求 4）

**是否繼續修復剩餘需求？**
如果你想繼續，我可以立即開始修復需求 3 和 4。

如果你想先測試，可以：
1. Build & Run
2. 測試休息計時器
3. 記錄一些訓練
4. 檢查三項推估
5. 測試重量單位切換
6. 告訴我哪些還有問題

---

**文件更新日期**: 2025-10-29

