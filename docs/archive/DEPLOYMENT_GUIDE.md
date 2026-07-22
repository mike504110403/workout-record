# WorkoutRecord 部署指南

## 📚 目錄
1. [環境說明](#環境說明)
2. [開發環境部署](#開發環境部署)
3. [生產環境部署](#生產環境部署)
4. [上架流程](#上架流程)
5. [版本更新流程](#版本更新流程)
6. [常見問題](#常見問題)

---

## 環境說明

### Debug (開發環境)
- **用途**: 日常開發和測試
- **特點**:
  - 使用模擬器測試登入
  - 詳細的 Log 輸出
  - Firebase Remote Config 立即獲取
  - 數據保留 7 天（測試用）
- **Firebase**: 使用 Development 專案
- **API**: `http://localhost:8080/api`

### Release (生產環境)
- **用途**: TestFlight 測試和 App Store 上架
- **特點**:
  - 必須使用真實設備
  - 優化的代碼和性能
  - Firebase Remote Config 1 小時更新
  - 數據保留 30 天（免費用戶）
- **Firebase**: 使用 Production 專案
- **API**: `https://api.your-domain.com/api`

---

## 開發環境部署

### 1. 準備工作

```bash
# 1. Clone 專案
git clone <your-repo>
cd workout-record

# 2. 打開專案
cd ios/WorkoutRecord
open WorkoutRecord.xcodeproj
```

### 2. Firebase 配置 (Development)

1. 前往 [Firebase Console](https://console.firebase.google.com/)
2. 選擇或創建 **Development** 專案
3. 下載 `GoogleService-Info.plist`
4. 放置在 `ios/WorkoutRecord/WorkoutRecord/GoogleService-Info.plist`

### 3. Xcode 配置

1. **選擇 Scheme**: `WorkoutRecord`
2. **選擇目標**: 模擬器或真實設備
3. **Build Configuration**: 
   - Edit Scheme → Run → Build Configuration: **Debug**
4. **Signing**: 
   - 選擇你的 Team
   - Bundle Identifier: `com.yourcompany.WorkoutRecord`

### 4. 運行

```
Command + R (或點擊 Run 按鈕)
```

### 5. 驗證

- [ ] App 成功啟動
- [ ] 環境顯示 "開發環境"
- [ ] 模擬器測試登入正常
- [ ] Firebase Analytics 有數據

---

## 生產環境部署

### 1. 環境切換準備

#### 更新 Firebase 配置

1. 前往 [Firebase Console](https://console.firebase.google.com/)
2. 選擇或創建 **Production** 專案
3. 下載 **生產環境** 的 `GoogleService-Info.plist`
4. **備份開發環境配置**:
   ```bash
   cp ios/WorkoutRecord/WorkoutRecord/GoogleService-Info.plist \
      ios/WorkoutRecord/WorkoutRecord/GoogleService-Info.dev.plist
   ```
5. **替換為生產配置**:
   ```bash
   cp path/to/production/GoogleService-Info.plist \
      ios/WorkoutRecord/WorkoutRecord/GoogleService-Info.plist
   ```

#### 更新 App Store URL

編輯 `EnvironmentConfig.swift`:
```swift
static var appStoreURL: String {
    "https://apps.apple.com/app/id<YOUR_APP_ID>"  // 替換為實際 App ID
}
```

編輯 `VersionManager.swift`:
```swift
@Published var updateURL = "https://apps.apple.com/app/id<YOUR_APP_ID>"
```

#### 更新 API URL（如果後端已部署）

編輯 `EnvironmentConfig.swift`:
```swift
case .production:
    return "https://api.your-domain.com/api"  // 替換為實際 API URL
```

### 2. 版本號設置

1. 打開 Xcode
2. 選擇 Target: `WorkoutRecord`
3. General → Identity:
   - **Version**: `1.0.0` (首次上架)
   - **Build**: `1` (首次上架)

### 3. Signing & Capabilities

1. **Signing**:
   - Team: 選擇你的 Apple Developer Team
   - Bundle Identifier: 確認與 App Store Connect 一致
   - ✅ Automatically manage signing

2. **Capabilities** (必須啟用):
   - ✅ Sign in with Apple
   - ✅ Push Notifications

3. **Optional** (未來需要時啟用):
   - ☐ iCloud
   - ☐ Background Modes

### 4. Archive

1. **選擇目標設備**: `Any iOS Device (arm64)`
2. **選擇 Scheme**: `WorkoutRecord`
3. **Product** → **Archive**
4. 等待 Archive 完成（5-10 分鐘）

### 5. 驗證 Archive

Archive 完成後，Organizer 會自動打開：

1. 選擇剛才的 Archive
2. 點擊 **Validate App**
3. 選擇 Distribution 方式: **App Store Connect**
4. 選擇 Signing 方式: **Automatically manage signing**
5. 點擊 **Validate**
6. 等待驗證完成

如果驗證通過，繼續下一步。

### 6. 上傳到 App Store Connect

1. 點擊 **Distribute App**
2. 選擇: **App Store Connect**
3. 選擇: **Upload**
4. 配置選項:
   - ✅ Upload your app's symbols (重要！用於崩潰分析)
   - ✅ Manage Version and Build Number
5. 點擊 **Upload**
6. 等待上傳完成（10-30 分鐘，取決於網速）

---

## 上架流程

### 1. App Store Connect 準備

#### 創建 App

1. 登入 [App Store Connect](https://appstoreconnect.apple.com/)
2. 點擊 **My Apps** → **+** → **New App**
3. 填寫信息:
   - **Platform**: iOS
   - **Name**: WorkoutRecord
   - **Primary Language**: Traditional Chinese
   - **Bundle ID**: 選擇你的 Bundle ID
   - **SKU**: `workout-record-001` (唯一識別碼)

#### 填寫 App 信息

1. **App Information**:
   - Name: `WorkoutRecord`
   - Subtitle: `專業的健身訓練記錄工具`
   - Category: 
     - Primary: Health & Fitness
     - Secondary: Productivity

2. **Pricing and Availability**:
   - Price: Free
   - Availability: All Countries/Regions

3. **App Privacy**:
   - Privacy Policy URL: `https://your-website.com/privacy` (必須)
   - 填寫數據收集問卷

#### 準備截圖

**必要尺寸** (可用 iPhone 15 Pro Max 截圖):
- 6.7" Display: 1290 x 2796 (必須)
- 6.5" Display: 1284 x 2778 (可選)

**建議截圖**:
1. Dashboard (首頁)
2. 訓練中畫面
3. 數據統計圖表
4. 三大項進度
5. 歷史記錄

**製作方式**:
```bash
# 在模擬器或真實設備截圖
Command + S (模擬器)
側邊按鈕 + 音量上鍵 (真實設備)
```

#### 填寫版本信息

1. **What's New in This Version**:
```
首次發布！

🎉 核心功能:
• 詳細記錄每組訓練數據
• 可視化訓練進度和容量趨勢
• 三大項（深蹲、臥推、硬舉）專門追蹤
• 豐富的動作庫和自定義動作
• 訓練模板快速開始
• 成就系統激勵持續訓練

💪 特色亮點:
• 簡潔直觀的設計
• 完全離線使用
• 尊重用戶隱私
• 支持深色模式
```

2. **Description**: (見 PRE_LAUNCH_CONFIGURATION.md)

3. **Keywords**: `健身,訓練,健身房,重訓,記錄,體重,三大項,深蹲,臥推,硬舉`

4. **Support URL**: `https://your-website.com/support`

### 2. TestFlight 測試

1. **選擇 Build**:
   - 上傳完成後（處理需要 10-30 分鐘）
   - 在 **TestFlight** 標籤選擇 Build

2. **添加測試信息**:
   - What to Test: 描述新功能和需要測試的項目
   - Test Details: 填寫測試用戶需要知道的信息

3. **內部測試**:
   - 添加內部測試用戶（最多 100 人）
   - 發送測試邀請
   - 收集反饋

4. **外部測試** (可選):
   - 創建外部測試組
   - 添加測試用戶（最多 10,000 人）
   - 需要 Apple 審核（通常 24-48 小時）

### 3. 提交審核

1. **準備審核信息**:
   - **App Review Information**:
     - Contact Information: 你的聯絡方式
     - Demo Account: 如需要，提供測試帳號
     - Notes: 補充說明

2. **提交審核**:
   - 確認所有信息正確
   - 點擊 **Submit for Review**
   - 確認提交

3. **審核狀態**:
   - **Waiting for Review**: 等待審核（1-3 天）
   - **In Review**: 審核中（1-2 天）
   - **Pending Developer Release**: 審核通過，等待發布
   - **Ready for Sale**: 已上架

### 4. 發布

審核通過後：

1. **自動發布**: 審核通過後自動上架
2. **手動發布**: 選擇發布時間，點擊 **Release This Version**

---

## 版本更新流程

### 1. 準備新版本

```bash
# 1. 創建新分支
git checkout -b release/v1.1.0

# 2. 更新版本號
# 在 Xcode 中:
# General → Identity → Version: 1.1.0
# General → Identity → Build: 1 (或遞增)

# 3. 更新代碼
# 實現新功能、修復 Bug

# 4. 更新 CHANGELOG
echo "## Version 1.1.0\n### New Features\n- Feature 1\n### Bug Fixes\n- Fix 1" >> CHANGELOG.md

# 5. Commit
git add .
git commit -m "Release v1.1.0"
git push origin release/v1.1.0
```

### 2. 版本更新前自動備份

**已實現**: 在 `AppState.init()` 中自動執行

```swift
private func checkVersionAndBackup() {
    let currentVersion = Bundle.main.appVersion
    let savedVersion = UserDefaults.standard.string(forKey: "LastAppVersion")
    
    if let saved = savedVersion, saved != currentVersion {
        CoreDataBackupService.shared.autoBackup()
    }
    
    UserDefaults.standard.set(currentVersion, forKey: "LastAppVersion")
}
```

### 3. Archive 和上傳

重複 [生產環境部署](#生產環境部署) 的步驟 4-6

### 4. App Store Connect

1. 在 **App Store Connect** 點擊 **+** → **New Version**
2. 輸入版本號: `1.1.0`
3. 填寫 **What's New in This Version**
4. 選擇新的 Build
5. 提交審核

### 5. Firebase Remote Config 更新

如需強制更新：

1. 前往 Firebase Console → Remote Config
2. 更新參數:
   - `ios_latest_version`: `1.1.0`
   - `ios_minimum_version`: `1.0.0` (或更高)
   - `ios_force_update`: `true` (如需強制)
   - `ios_update_message_zh`: 更新說明
3. 發布配置

---

## 常見問題

### Q1: Archive 時出現 "Signing for WorkoutRecord requires a development team"

**解決方法**:
1. 在 Xcode → Signing & Capabilities
2. 選擇你的 Team
3. 確保 Bundle Identifier 已在 Apple Developer 註冊

### Q2: 上傳失敗 "Invalid Binary"

**可能原因**:
- 缺少 App Icon
- Bundle Identifier 不匹配
- Minimum Deployment Target 過低

**解決方法**:
1. 確認 App Icon 已設置所有尺寸
2. 確認 Bundle Identifier 與 App Store Connect 一致
3. 確認 Deployment Target 為 iOS 16.0+

### Q3: Firebase Auth 在模擬器無法使用

**這是正常的**:
- Apple Sign In 需要真實設備
- 模擬器使用測試登入流程
- 在 TestFlight 或真實設備測試完整流程

### Q4: Remote Config 沒有生效

**解決方法**:
1. 確認 Firebase 專案配置正確
2. 確認 Remote Config 已發布
3. Debug 模式立即生效，Release 模式需要等待（最多 1 小時）
4. 強制重新獲取: `versionManager.resetCheckStatus()`

### Q5: 審核被拒絕

**常見原因**:
- 缺少隱私權政策
- 功能描述不清楚
- 測試帳號無效
- App 崩潰

**解決方法**:
1. 仔細閱讀拒絕原因
2. 修復問題
3. 回覆審核團隊
4. 重新提交

### Q6: 如何回退到開發環境？

**步驟**:
```bash
# 1. 恢復開發環境的 Firebase 配置
cp ios/WorkoutRecord/WorkoutRecord/GoogleService-Info.dev.plist \
   ios/WorkoutRecord/WorkoutRecord/GoogleService-Info.plist

# 2. 在 Xcode 中切換 Build Configuration 為 Debug
# Edit Scheme → Run → Build Configuration: Debug

# 3. Clean Build
Command + Shift + K

# 4. 重新運行
Command + R
```

---

## 檢查清單

### 上架前

- [ ] 所有功能測試通過
- [ ] UI/UX 完善
- [ ] 性能優化完成
- [ ] Firebase Production 配置已替換
- [ ] App Store URL 已更新
- [ ] 版本號已設置
- [ ] Signing 已配置
- [ ] Archive 成功
- [ ] Validate 通過
- [ ] 上傳到 App Store Connect 成功
- [ ] 截圖已準備
- [ ] App 描述已填寫
- [ ] 隱私權政策已發布
- [ ] TestFlight 測試完成
- [ ] 審核信息已填寫
- [ ] 提交審核

### 審核通過後

- [ ] 檢查 App Store 頁面
- [ ] 測試安裝和運行
- [ ] 監控 Analytics 數據
- [ ] 監控崩潰率
- [ ] 回應用戶評論
- [ ] 準備下個版本

---

**文件版本**: 1.0  
**最後更新**: 2025-10-29  
**維護者**: Development Team  

🚀 祝你上架順利！

