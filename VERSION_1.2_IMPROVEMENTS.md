# 版本 1.2 改進計畫

## 📋 問題清單

這些是在準備 1.1 版上架時發現的問題，建議在 1.2 版本中修復。

---

## 🔴 高優先級（影響核心功能）

### 1. 訓練時：動作沒有組數時不能按「完成動作」

**問題描述：**
- 用戶可以新增動作但不新增任何組數
- 直接點擊「完成動作」會產生空的訓練記錄

**影響：**
- 產生無意義的資料
- 影響統計準確性

**建議修復：**
```swift
// 在 WorkoutView 中加入驗證
Button("完成動作") {
    // 檢查是否至少有一組
    if currentExercise.sets.isEmpty {
        showAlert = true
        alertMessage = "請至少記錄一組訓練"
        return
    }
    finishExercise()
}
```

**檔案位置：**
- `WorkoutView.swift` 或相關的訓練視圖

---

### 2. 動作及組的左滑編輯/刪除功能未實作

**問題描述：**
- 使用教學提到「向左滑動可編輯或刪除」
- 但實際功能未實作

**建議實作：**
```swift
// 訓練中的動作列表
List {
    ForEach(workout.exercises) { exercise in
        ExerciseRow(exercise: exercise)
    }
    .onDelete { indexSet in
        // 刪除動作
    }
}

// 組數列表
List {
    ForEach(exercise.sets) { set in
        SetRow(set: set)
            .swipeActions {
                Button("刪除", role: .destructive) {
                    deleteSet(set)
                }
                Button("編輯") {
                    editSet(set)
                }
            }
    }
}
```

**檔案位置：**
- `WorkoutView.swift`
- `AddSetSheet.swift`

---

### 3. 動作及組在完成訓練前都應可編輯和刪除

**問題描述：**
- 目前可能只有特定階段可以編輯
- 應該在整個訓練過程中都可以修改

**建議實作：**
- 訓練進行中：可編輯、可刪除
- 完成訓練後：變成歷史記錄（需要特殊權限才能修改）

---

### 4. 輸入時跳出的鍵盤關不掉

**問題描述：**
- 之前已加入 `.dismissKeyboardOnInteraction()`
- 但鍵盤仍然關不掉

**可能原因：**
1. 修飾符位置不正確
2. TextField 的 FocusState 未處理
3. 某些視圖攔截了手勢

**建議檢查：**
```swift
// 檢查是否有使用 @FocusState
@FocusState private var focusedField: Field?

// 在適當的地方清除 focus
focusedField = nil

// 或在點擊其他地方時
.onTapGesture {
    focusedField = nil
}
```

**檔案位置：**
- `AddSetSheet.swift`
- `BodyWeightView.swift`
- `ProfileView.swift`

---

## 🟡 中優先級（影響使用體驗）

### 5. 更新隱私權相關說明

**需要更新的位置：**

#### 5.1 新手導引（OnboardingView）
```swift
// 目前的隱私說明
"✅ 我們不會收集您的個人資訊"

// 應改為
"✅ 您的資料安全儲存在 Firebase"
"✅ 僅收集必要資訊用於 App 功能"
"✅ 不會用於廣告或追蹤目的"
```

#### 5.2 登入頁面（AppleIDLoginView）
```swift
// 更新隱私說明區塊
VStack(spacing: 12) {
    Text("隱私保護")
        .font(.headline)
    
    VStack(alignment: .leading, spacing: 8) {
        PrivacyPoint(text: "使用 Apple ID 安全登入")
        PrivacyPoint(text: "資料加密儲存於 Firebase")
        PrivacyPoint(text: "僅收集必要的帳號資訊")
        PrivacyPoint(text: "不用於廣告或第三方分享")
    }
}
```

#### 5.3 設定頁面 - 關於/隱私
- 加入隱私權政策連結
- 說明收集的資料類型
- 說明資料用途

**檔案位置：**
- `OnboardingView.swift`
- `AppleIDLoginView.swift`
- `AboutView.swift`
- 新增 `PrivacyPolicyView.swift`

---

### 6. 個人資料頁顯示 Apple ID 帳號資訊

**問題描述：**
- 目前個人資料頁可能沒有顯示 Apple ID 的資訊
- 或顯示不完整

**建議實作：**
```swift
// ProfileView.swift
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
            Text("Apple ID")
                .font(.caption2)
                .foregroundColor(.blue)
        }
        .padding(.leading, 8)
    }
    .padding(.vertical, 8)
}

Section("基本資料") {
    TextField("姓名", text: $profile.name)
    // ... 其他欄位
}
```

**需要從 Firebase 讀取的資料：**
- Apple ID 姓名（已在 AppleIDAuth）
- Apple ID 電子郵件（已在 AppleIDAuth）
- 其他用戶設定的資料

**檔案位置：**
- `SettingsView.swift` 中的 `ProfileView`

---

### 7. 模板的編輯和刪除功能未實作

**問題描述：**
- 可以建立模板
- 但無法編輯或刪除現有模板

**建議實作：**
```swift
// WorkoutTemplateView.swift
List {
    ForEach(templates) { template in
        NavigationLink(destination: TemplateDetailView(template: template)) {
            TemplateRow(template: template)
        }
        .swipeActions {
            Button("刪除", role: .destructive) {
                deleteTemplate(template)
            }
            Button("編輯") {
                editTemplate(template)
            }
        }
    }
}
```

**檔案位置：**
- `WorkoutTemplateView.swift`
- 可能需要新增 `EditTemplateView.swift`

---

## 🎯 建議處理順序

### 選項 A：先上 1.1 版，再修復（推薦）

**優點：**
- 快速上架，收集真實用戶反饋
- 新功能（使用教學、版本檢查）先上線
- 問題修復可以在 1.2 版處理

**缺點：**
- 用戶可能遇到上述問題
- 需要再次審核

**時程：**
- 現在：上架 1.1 版
- 1-2 週：修復所有問題
- 提交 1.2 版

### 選項 B：修復完再上架

**優點：**
- 提供更完善的使用體驗
- 減少負面評價風險

**缺點：**
- 延遲上架時間（估計需要 2-3 天）
- 版本檢查等新功能延後上線

**時程：**
- 2-3 天：修復所有問題
- 測試後上架 1.1 版

---

## 📝 修復預估時間

| 問題 | 預估時間 | 難度 |
|-----|---------|------|
| 1. 動作組數驗證 | 30 分鐘 | ⭐ 簡單 |
| 2. 左滑編輯/刪除 | 2 小時 | ⭐⭐ 中等 |
| 3. 編輯權限調整 | 1 小時 | ⭐ 簡單 |
| 4. 鍵盤關閉修復 | 1 小時 | ⭐⭐ 中等 |
| 5. 隱私權更新 | 1.5 小時 | ⭐ 簡單 |
| 6. 個人資料顯示 | 1 小時 | ⭐ 簡單 |
| 7. 模板編輯/刪除 | 2 小時 | ⭐⭐ 中等 |
| **總計** | **9 小時** | |

---

## 🤔 您的決定？

請告訴我您想要：

### A. 先上 1.1 版，這些問題在 1.2 版修復
- 優點：快速上架
- 缺點：用戶可能遇到問題

### B. 修復完再上 1.1 版
- 優點：更完善的體驗
- 缺點：延遲 2-3 天

### C. 只修復最嚴重的（1, 4, 5），其他留到 1.2
- 優點：平衡速度和品質
- 預估時間：3-4 小時

---

**建議：選項 C（修復關鍵問題）**

最嚴重的問題：
1. ✅ 動作組數驗證（影響資料品質）
2. ✅ 鍵盤關閉（影響使用體驗）
3. ✅ 隱私權更新（法規要求）

其他功能（左滑編輯、模板管理等）可以在 1.2 版加入，作為「功能增強」而非「錯誤修復」。

---

請告訴我您的選擇，我會立即開始處理！🚀

