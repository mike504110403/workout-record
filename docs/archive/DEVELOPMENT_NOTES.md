# 開發筆記

## 2025-10-21 開發進度

### ✅ 已完成的工作

#### 1. 訓練詳情頁修復
- 修改 `WorkoutDetailView` 從 `WorkoutRepository` 加載真實數據
- 移除 mock 數據
- 實現刪除功能
- 添加載入狀態顯示

#### 2. 動作庫肌群分類
為所有 70+ 個系統動作添加：
- `primaryMuscleGroup`（主要肌群）
- `movementPattern`（動作模式）

涵蓋的動作類別：
- 胸部：12 個動作 (push, isolation)
- 背部：11 個動作 (pull, isolation)
- 腿部：12 個動作 (squat, hinge, isolation)
- 肩部：10 個動作 (push, pull, isolation)
- 手臂：11 個動作 (push, pull, isolation)
- 核心：10 個動作 (isolation)

#### 3. 日曆功能實現
在 `HistoryView` 中實現：
- 月曆視圖切換
- 月份切換功能
- 訓練日期標記（藍點）
- 點擊日期查看當日訓練
- 週日至週六的正確排列

#### 4. 調試工具添加
添加詳細的調試日誌：
- `WorkoutViewModel.saveWorkout()`：保存訓練時的數據檢查
- `WorkoutRepository.convertToModel()`：載入 exercise 對象的日誌
- `VolumeChartViewModel.aggregateVolumeByDate()`：肌群數據聚合日誌

#### 5. CoreData 版本管理
- 升級資料庫版本到 `2.2`
- 實現自動資料庫重置機制
- 確保模型變更時正確遷移

### 🐛 待解決的問題

#### 肌群篩選功能異常
**問題描述**：
- 選擇「總容量」：✅ 有數據
- 選擇「胸部」：❌ 無數據

**可能原因**：
1. 保存訓練時 `exercise` 對象為 `nil`
2. 載入訓練時無法找到對應的 exercise
3. exercise 的 `primaryMuscleGroup` 為 `nil`

**調試計劃**：
1. 查看保存訓練時的控制台輸出
2. 查看載入訓練時的控制台輸出
3. 查看肌群聚合時的控制台輸出
4. 根據日誌確定問題環節

**相關代碼**：
- `WorkoutViewModel.saveWorkout()` - 第 211 行：`exercise: nil`
- `WorkoutRepository.convertToModel()` - 第 251 行：載入 exercise
- `VolumeChartViewModel.aggregateVolumeByDate()` - 第 139-143 行：肌群聚合

### 📝 技術債務

1. **ExercisePickerViewModel** 仍使用部分 mock 數據（favorite 功能）
2. **CustomExercise** 儲存在 UserDefaults，未來應遷移到 CoreData
3. **PR 功能** 只實現了追蹤，未實現 UI 顯示
4. **目標功能** UI 已完成，但與訓練記錄的關聯還需加強

### 🔧 代碼改進建議

#### 1. WorkoutViewModel 保存邏輯
當前問題：
```swift
return WorkoutExercise(
    // ...
    exerciseId: exerciseVM.exerciseId,
    exercise: nil,  // ⚠️ 這裡是 nil
    // ...
)
```

可能的解決方案：
```swift
// 方案 1：在保存前加載 exercise
let exerciseRepo = ExerciseRepository()
let exercise = try? exerciseRepo.fetchById(exerciseVM.exerciseId)

return WorkoutExercise(
    // ...
    exerciseId: exerciseVM.exerciseId,
    exercise: exercise,  // ✅ 有數據
    // ...
)

// 方案 2：在 Repository 保存時自動關聯
// 在 WorkoutRepository.create() 中處理 exercise 關聯
```

#### 2. 數據一致性
確保以下流程的數據完整性：
1. 選擇/添加動作 → `WorkoutViewModel`
2. 記錄訓練 → `WorkoutViewModel.saveWorkout()`
3. 保存到 CoreData → `WorkoutRepository.create()`
4. 讀取訓練 → `WorkoutRepository.fetchById()`
5. 顯示數據 → `WorkoutDetailView` / `VolumeChartView`

### 📊 測試場景

#### 測試 1：新訓練記錄
1. 開始訓練（從模板）
2. 記錄幾組數據
3. 完成訓練
4. 查看控制台日誌
5. 檢查「數據」頁面的肌群篩選

#### 測試 2：歷史記錄
1. 進入「歷史」頁面
2. 點擊訓練記錄
3. 檢查是否顯示正確的動作名稱
4. 檢查容量分布是否正確

#### 測試 3：日曆視圖
1. 切換到日曆視圖
2. 檢查有訓練的日期是否標記
3. 點擊日期查看訓練
4. 切換月份測試

### 🎯 明天的工作計劃

1. **優先級 1**：修復肌群篩選功能
   - 分析控制台日誌
   - 確定問題環節
   - 實施修復方案
   - 測試驗證

2. **優先級 2**：代碼優化
   - 清理調試日誌（或改為條件編譯）
   - 優化數據加載流程
   - 添加錯誤處理

3. **優先級 3**：功能完善
   - PR 功能 UI 顯示
   - 目標達成提醒
   - 訓練統計優化

### 💡 技術筆記

#### CoreData 數據加載策略
- 使用 Repository 模式統一數據訪問
- 在 `convertToModel()` 中延遲加載關聯對象
- 注意循環引用問題（如 Workout ↔ Exercise）

#### SwiftUI 數據刷新
- 使用 `NotificationCenter` 跨 View 通知
- `.workoutCompleted` 通知觸發數據刷新
- `@StateObject` vs `@ObservedObject` 的選擇

#### 圖表數據處理
- 按日期聚合數據
- 按肌群分組統計
- 時間範圍過濾

### 🔍 調試技巧

#### 查看 CoreData 數據
```swift
// 在 Repository 中添加
func debugPrintAll() {
    let workouts = try? fetchAll()
    for workout in workouts ?? [] {
        print("Workout: \(workout.id)")
        for ex in workout.exercises {
            print("  - Exercise: \(ex.exerciseId)")
            print("    - exercise object: \(ex.exercise?.name ?? "nil")")
            print("    - muscle group: \(ex.exercise?.primaryMuscleGroup?.displayName ?? "nil")")
        }
    }
}
```

#### 檢查數據庫文件
```bash
# 找到 simulator 的數據目錄
xcrun simctl get_app_container booted com.your.app data

# 使用 SQLite 工具查看
sqlite3 path/to/WorkoutRecord.sqlite
```

### 📚 參考資料

- [CoreData Programming Guide](https://developer.apple.com/documentation/coredata)
- [SwiftUI Data Flow](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)
- [Swift Charts Documentation](https://developer.apple.com/documentation/charts)

---

**備註**：本文件記錄開發過程中的重要決策、問題和解決方案，供未來參考。

