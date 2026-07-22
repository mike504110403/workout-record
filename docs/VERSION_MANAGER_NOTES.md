# 版本管理系統說明

## 當前實現狀態

### ✅ 已實現
- 版本檢查邏輯
- 強制更新 UI
- 可選更新 UI
- App Store 跳轉
- DEBUG/RELEASE 環境支援
- 自動檢查機制

### 📝 簡化實現
為了避免增加額外的 Firebase 依賴，當前版本使用**硬編碼的預設值**：

```swift
private let defaultMinimumVersion = "1.0.0"
private let defaultLatestVersion = "1.0.0"
private let defaultForceUpdate = false
private let defaultUpdateMessage = "新版本包含重要更新和錯誤修復"
```

### 如何手動控制版本更新

#### 方法 1: 修改 VersionManager.swift（簡單但需要重新發布）

如果你想要強制用戶更新到新版本，修改 `VersionManager.swift` 中的預設值：

```swift
// 例如：要求用戶必須使用 1.1.0 或更高版本
private let defaultMinimumVersion = "1.1.0"  // 改成新的最低版本
private let defaultLatestVersion = "1.1.0"   // 改成最新版本
private let defaultForceUpdate = true        // 設為 true 強制更新
```

**注意**: 這需要發布新版本才能生效，無法遠端控制。

#### 方法 2: 未來整合 Firebase Remote Config（推薦但需要額外工作）

如果需要遠端控制更新策略，可以在未來版本整合 Firebase Remote Config：

1. **添加依賴**（在 Xcode 中）:
   - File → Add Package Dependencies
   - 搜尋 Firebase
   - 選擇 `FirebaseRemoteConfig`

2. **恢復原始代碼**（備份在 git history）

3. **在 Firebase Console 配置參數**

**優點**: 
- 可以遠端即時控制
- 不需要發布新版本
- 可以針對不同用戶群組設置不同策略

**缺點**:
- 增加依賴大小（~5MB）
- 需要 Firebase 配置
- 首次啟動需要網路

---

## 當前運作方式

### 正常情況（版本相同）
```
用戶版本: 1.0.0
最低版本: 1.0.0
最新版本: 1.0.0
→ 不顯示任何更新提示 ✅
```

### 可選更新
```
用戶版本: 1.0.0
最低版本: 1.0.0
最新版本: 1.1.0
forceUpdate: false
→ 顯示可選更新彈窗（可關閉） 💡
```

### 強制更新
```
用戶版本: 1.0.0
最低版本: 1.1.0
→ 顯示強制更新全屏（無法關閉） ⚠️
```

或

```
用戶版本: 1.0.0
最低版本: 1.0.0
最新版本: 1.1.0
forceUpdate: true
→ 顯示強制更新全屏（無法關閉） ⚠️
```

---

## 測試方式

### 測試可選更新
1. 修改 `VersionManager.swift`:
```swift
private let defaultLatestVersion = "2.0.0"  // 設為高於當前版本
private let defaultForceUpdate = false
```
2. 重新運行 App
3. 應該看到可選更新彈窗

### 測試強制更新
1. 修改 `VersionManager.swift`:
```swift
private let defaultMinimumVersion = "2.0.0"  // 設為高於當前版本
```
2. 重新運行 App
3. 應該看到強制更新全屏，無法關閉

---

## 版本更新策略建議

### 小更新（Bug 修復）
```
1.0.0 → 1.0.1
策略: 不提示更新
```

### 功能更新
```
1.0.0 → 1.1.0
策略: 可選更新
設置: defaultLatestVersion = "1.1.0"
      defaultForceUpdate = false
```

### 重大更新
```
1.0.0 → 2.0.0
策略: 強制更新
設置: defaultMinimumVersion = "2.0.0"
```

### 關鍵安全修復
```
任何版本 → 新版本
策略: 強制更新
設置: defaultMinimumVersion = "新版本"
      defaultForceUpdate = true
```

---

## 上線後的版本管理流程

### 當前版本在 App Store: v1.0.0

#### 發布 v1.1.0（可選更新）
1. 開發完成功能
2. 修改 Xcode 中的版本號: `1.1.0`
3. Archive 並上傳
4. **不修改** `VersionManager.swift`（讓 v1.0.0 用戶可選更新）
5. 審核通過後發布

#### 發布 v1.2.0（強制 v1.0.0 用戶更新）
1. 開發完成功能
2. 修改 Xcode 中的版本號: `1.2.0`
3. **修改** `VersionManager.swift`:
   ```swift
   private let defaultMinimumVersion = "1.1.0"  // v1.0.0 必須更新
   private let defaultLatestVersion = "1.2.0"
   ```
4. Archive 並上傳
5. 審核通過後發布
6. v1.0.0 用戶打開 App 會被強制更新

---

## 替代方案：後端 API 控制（進階）

如果你有自己的後端，可以創建一個簡單的版本檢查 API：

### API 設計
```
GET /api/version/check?platform=ios&version=1.0.0

Response:
{
  "minimum_version": "1.0.0",
  "latest_version": "1.1.0",
  "force_update": false,
  "update_message": "新版本包含許多改進",
  "update_url": "https://apps.apple.com/app/id123456"
}
```

### 修改 VersionManager
在 `checkVersion()` 中添加 API 調用，替換預設值。

**優點**:
- 完全控制
- 不依賴 Firebase
- 可以記錄用戶版本分佈

**缺點**:
- 需要自己的後端
- 需要維護 API

---

## 結論

**當前實現是最簡單且足夠的方案**，適合以下場景：
- ✅ 初期上線
- ✅ 不需要頻繁強制更新
- ✅ 減少依賴和 App 大小
- ✅ 簡化維護

**未來如果需要更靈活的控制**，再考慮整合：
- Firebase Remote Config（推薦給小團隊）
- 自建後端 API（推薦給有後端的團隊）

目前的實現**完全符合上線需求**！✅

