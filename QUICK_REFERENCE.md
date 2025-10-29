# WorkoutRecord 快速參考

## 📁 專案結構

```
workout-record/
├── ios/WorkoutRecord/WorkoutRecord/Sources/
│   ├── Services/          # 核心服務
│   │   ├── VersionManager.swift          ⭐ 版本管理
│   │   ├── FirebaseAuthService.swift     ⭐ Firebase 認證
│   │   ├── AnalyticsService.swift        ⭐ 分析服務
│   │   ├── EnvironmentConfig.swift       ⭐ 環境配置
│   │   └── CoreDataBackupService.swift   ⭐ 數據備份
│   ├── Views/             # UI 視圖
│   │   ├── Update/UpdateView.swift       ⭐ 更新提示
│   │   └── Auth/AppleIDLoginView.swift   ⭐ 登入頁面
│   ├── ViewModels/        # 視圖模型
│   ├── Models/            # 數據模型
│   └── Utils/             # 工具函數
│       └── UIInteractionTracker.swift    ⭐ UI 追蹤
└── docs/                  # 文檔
    ├── LAUNCH_READY_SUMMARY.md           ⭐ 上線準備總結
    ├── PRE_LAUNCH_CONFIGURATION.md       ⭐ 配置清單
    ├── DEPLOYMENT_GUIDE.md               ⭐ 部署指南
    └── PRE_LAUNCH_CHECKLIST.md           ⭐ 檢查清單

⭐ = 上線準備新增/更新的文件
```

---

## 🔧 關鍵配置

### Firebase Remote Config (必須設置)

```json
{
  "ios_minimum_version": "1.0.0",
  "ios_latest_version": "1.0.0",
  "ios_force_update": false,
  "ios_update_message_zh": "新版本包含重要更新和錯誤修復",
  "ios_update_url": "https://apps.apple.com/app/id<YOUR_APP_ID>"
}
```

### EnvironmentConfig.swift (待替換)

```swift
// Line ~40: 生產環境 API URL
case .production:
    return "https://api.your-domain.com/api"  // ⚠️ 替換

// Line ~75: App Store URL
static var appStoreURL: String {
    "https://apps.apple.com/app/id<YOUR_APP_ID>"  // ⚠️ 替換
}
```

### VersionManager.swift (待替換)

```swift
// Line ~20: 預設 App Store URL
@Published var updateURL = "https://apps.apple.com/app/id"  // ⚠️ 替換
```

---

## 🚀 快速命令

### 開發環境

```bash
# 打開專案
cd ios/WorkoutRecord
open WorkoutRecord.xcodeproj

# 運行配置檢查
cd ios
./check_config.sh

# 清理建置
Command + Shift + K (Xcode)

# 運行
Command + R (Xcode)
```

### 環境切換

```bash
# 備份開發配置
cp ios/WorkoutRecord/WorkoutRecord/GoogleService-Info.plist \
   ios/WorkoutRecord/WorkoutRecord/GoogleService-Info.dev.plist

# 替換生產配置
cp path/to/production/GoogleService-Info.plist \
   ios/WorkoutRecord/WorkoutRecord/GoogleService-Info.plist

# 在 Xcode:
# Edit Scheme → Run → Build Configuration: Release
```

### Archive & Upload

```bash
# 1. 選擇 Any iOS Device (arm64)
# 2. Product → Archive
# 3. Organizer → Distribute App → App Store Connect
# 4. Upload
```

---

## ✅ 上架前檢查清單（超簡版）

### 必須配置
- [ ] Firebase Remote Config 已設置
- [ ] 生產環境 API URL 已更新
- [ ] App Store URL 已更新
- [ ] GoogleService-Info.plist 已替換為生產版
- [ ] Bundle Identifier 正確
- [ ] Signing & Capabilities 已配置
- [ ] Sign in with Apple 已啟用

### 必須準備
- [ ] 截圖（3-10 張，6.7" Display）
- [ ] App 描述（4000 字元）
- [ ] 關鍵詞（100 字元）
- [ ] 隱私權政策 URL
- [ ] 支援 URL

### 必須測試
- [ ] 真實設備登入流程
- [ ] 訓練記錄完整流程
- [ ] 重量單位切換
- [ ] 深色/淺色模式

---

## 📞 緊急聯繫

### 建置錯誤
1. Clean Build Folder: `Command + Shift + K`
2. Delete Derived Data: `~/Library/Developer/Xcode/DerivedData`
3. 重新打開 Xcode

### Firebase 問題
- Console: https://console.firebase.google.com/
- 檢查配置文件是否正確
- 檢查環境 (DEBUG/RELEASE)

### App Store Connect
- URL: https://appstoreconnect.apple.com/
- 狀態檢查: My Apps → WorkoutRecord

### 文檔
- **詳細配置**: `docs/PRE_LAUNCH_CONFIGURATION.md`
- **完整指南**: `docs/DEPLOYMENT_GUIDE.md`
- **功能總結**: `docs/LAUNCH_READY_SUMMARY.md`
- **檢查清單**: `docs/PRE_LAUNCH_CHECKLIST.md`

---

## 🔢 版本號規則

### 格式
- **Version**: `MAJOR.MINOR.PATCH` (例: `1.0.0`)
- **Build**: 整數遞增 (例: `1`, `2`, `3`)

### 範例
| 更新類型 | Version | Build | 說明 |
|---------|---------|-------|------|
| 首次發布 | 1.0.0 | 1 | 初始版本 |
| Bug 修復 | 1.0.1 | 2 | 小更新 |
| 新功能 | 1.1.0 | 3 | 次要更新 |
| 重大更新 | 2.0.0 | 4 | 主要更新 |

---

## 🎯 核心功能速查

### 訓練記錄
```
開始訓練 → 添加動作 → 記錄組數 → 休息計時 → 完成訓練
```

### 數據追蹤
```
容量趨勢 | 個人紀錄 | 三大項進度 | 成就系統 | 體重記錄
```

### 自定義
```
動作庫管理 | 訓練模板 | 偏好設定 | 主題切換 | 單位切換
```

### 系統功能
```
Apple ID 登入 | 版本檢查 | 自動備份 | 分析追蹤 | 隱私保護
```

---

## 📊 關鍵指標

### 目標
- 崩潰率: < 0.1%
- 啟動時間: < 2s
- 記憶體: < 100MB
- 首日下載: > 100
- 7 日留存: > 30%
- App Store 評分: > 4.5 ⭐

### 監控
- Firebase Analytics: 用戶行為
- App Store Connect: 崩潰率、下載量
- Firestore: 用戶註冊、登入次數

---

## 🚨 常見錯誤解決

### "Signing requires a development team"
→ Xcode → Signing & Capabilities → 選擇 Team

### "Invalid Binary"
→ 確認 App Icon 已設置所有尺寸

### Firebase Auth 在模擬器無法使用
→ 這是正常的，需要真實設備測試

### Remote Config 沒生效
→ Debug 立即生效，Release 需等 1 小時

### Archive 失敗
→ 選擇 `Any iOS Device (arm64)`

---

## 📖 文檔導航

### 開發者
- **完整實現**: `docs/TECHNICAL_IMPLEMENTATION_PLAN.md`
- **架構說明**: `docs/TECH_STACK.md`
- **功能地圖**: `docs/FEATURE_MAP.md`

### 上線
- **配置清單**: `docs/PRE_LAUNCH_CONFIGURATION.md` ⭐
- **部署指南**: `docs/DEPLOYMENT_GUIDE.md` ⭐
- **檢查清單**: `docs/PRE_LAUNCH_CHECKLIST.md` ⭐
- **功能總結**: `docs/LAUNCH_READY_SUMMARY.md` ⭐

### 發布
- **Release Notes**: `RELEASE_NOTES_v1.0.0.md`
- **實現總結**: `IMPLEMENTATION_SUMMARY.md`

---

## 💡 提示

### 開發時
- 使用 `#if DEBUG` 區分開發/生產代碼
- Console 會自動打印環境配置
- 模擬器使用測試登入

### 測試時
- TestFlight 必須使用 Release 配置
- 真實設備測試完整流程
- 檢查各種尺寸設備

### 上線前
- 備份開發環境配置
- 更新所有 URL
- 運行配置檢查腳本
- 完整測試一遍

### 上線後
- 監控 Analytics 和崩潰率
- 及時回應用戶評論
- 準備下一版本

---

**準備好了嗎？開始吧！🚀**

**需要幫助？** 查看 `docs/DEPLOYMENT_GUIDE.md`

