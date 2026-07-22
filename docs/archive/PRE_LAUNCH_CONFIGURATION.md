# 上線前配置清單

## 📋 概述
本文件列出 WorkoutRecord App 上線前所有必須完成的配置項目。

---

## 1️⃣ Info.plist 配置

### 必須配置項目

```xml
<!-- Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- App 基本信息 -->
    <key>CFBundleDisplayName</key>
    <string>WorkoutRecord</string>
    
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    
    <key>CFBundleVersion</key>
    <string>1</string>
    
    <!-- Apple Sign In 必須 -->
    <key>NSAppleSignInUsageDescription</key>
    <string>我們使用 Apple Sign In 來安全地創建和管理您的帳號</string>
    
    <!-- Firebase 必須 -->
    <key>FirebaseAppDelegateProxyEnabled</key>
    <false/>
    
    <!-- 隱私權描述 -->
    <key>NSUserTrackingUsageDescription</key>
    <string>我們使用分析數據來改善 App 體驗</string>
    
    <key>NSHealthShareUsageDescription</key>
    <string>允許 App 讀取您的健康數據以提供更精確的訓練分析</string>
    
    <key>NSHealthUpdateUsageDescription</key>
    <string>允許 App 將訓練數據寫入健康 App</string>
    
    <!-- 相機使用（未來可能需要） -->
    <key>NSCameraUsageDescription</key>
    <string>用於拍攝訓練照片或掃描二維碼</string>
    
    <key>NSPhotoLibraryUsageDescription</key>
    <string>用於選擇照片上傳</string>
</dict>
</plist>
```

---

## 2️⃣ Firebase 配置

### GoogleService-Info.plist

**位置**: `ios/WorkoutRecord/WorkoutRecord/GoogleService-Info.plist`

**注意事項**:
1. **開發環境**: 使用開發專案的 `GoogleService-Info.plist`
2. **生產環境**: 上架前替換為生產專案的 `GoogleService-Info.plist`

### Firebase Remote Config 設置

在 Firebase Console 設置以下參數：

| 參數名稱 | 類型 | 預設值 | 說明 |
|---------|------|--------|------|
| `ios_minimum_version` | String | `1.0.0` | 最低支援版本 |
| `ios_latest_version` | String | `1.0.0` | 最新版本 |
| `ios_force_update` | Boolean | `false` | 是否強制更新 |
| `ios_update_message_zh` | String | `新版本包含重要更新和錯誤修復` | 更新提示訊息 |
| `ios_update_url` | String | `https://apps.apple.com/app/id` | App Store URL |

### Firebase Authentication

1. **啟用 Apple Sign In**:
   - Firebase Console → Authentication → Sign-in method
   - 啟用 "Apple" 提供商
   - 配置 Apple Developer 的 Service ID

2. **Firestore 安全規則**:
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // 用戶資料
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
      
      // 訂閱資料
      match /subscription/{document=**} {
        allow read: if request.auth != null && request.auth.uid == userId;
        allow write: if false; // 只能由後端寫入
      }
      
      // 設備資料
      match /devices/{document=**} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
    }
    
    // 其他集合預設拒絕
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

### Firebase Analytics

**已整合**: `AnalyticsService.swift` 已配置完成

**追蹤的事件**:
- `app_launch`: App 啟動
- `firebase_auth_signin`: Firebase 登入
- `firebase_user_created`: 新用戶創建
- `workout_start`: 訓練開始
- `workout_complete`: 訓練完成
- `achievement_unlocked`: 成就解鎖
- `button_tap`: 按鈕點擊
- `page_view`: 頁面瀏覽
- 更多... (見 `AnalyticsService.swift` 和 `UIInteractionTracker.swift`)

---

## 3️⃣ Xcode 專案配置

### Signing & Capabilities

1. **Bundle Identifier**: 
   - 格式: `com.yourcompany.WorkoutRecord`
   - 確保與 Apple Developer 帳號一致

2. **Team**: 選擇你的 Apple Developer Team

3. **Capabilities** (必須啟用):
   - ✅ Sign in with Apple
   - ✅ Push Notifications (未來訂閱功能需要)
   - ✅ Background Modes (未來需要)
     - ☑️ Remote notifications
   - ✅ iCloud (未來雲端同步需要，目前可不啟用)
     - ☑️ CloudKit
     - ☑️ Key-value storage

### Build Settings

#### Debug Configuration
```
SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG
OTHER_SWIFT_FLAGS = -DDEBUG
```

#### Release Configuration
```
SWIFT_OPTIMIZATION_LEVEL = -O
SWIFT_COMPILATION_MODE = wholemodule
```

### Deployment Target
```
iOS Deployment Target: 16.0
```

---

## 4️⃣ App Store Connect 配置

### App 信息

**App 名稱**: WorkoutRecord (或你的品牌名稱)

**副標題** (30 字元):
```
專業的健身訓練記錄工具
```

**描述** (4000 字元):
```
WorkoutRecord 是一款專為健身愛好者設計的訓練記錄應用。
無論你是新手還是專業運動員，都能輕鬆記錄每次訓練，追蹤進步。

🏋️ 核心功能:
• 訓練記錄 - 詳細記錄每組的重量、次數和休息時間
• 數據分析 - 可視化訓練容量、個人紀錄和進步趨勢
• 動作庫 - 內建豐富的動作庫，支持自定義動作
• 訓練模板 - 創建並使用訓練模板，提高訓練效率
• 三大項追蹤 - 專門追蹤深蹲、臥推、硬舉的進度
• 體重記錄 - 追蹤體重變化，配合訓練目標
• 成就系統 - 解鎖訓練成就，保持動力

💪 特色亮點:
• 簡潔直觀的界面設計
• 離線優先，本地數據存儲
• 尊重隱私，數據完全掌控
• 支持深色模式
• 單位切換（公斤/磅）

🎯 適合人群:
• 健身房訓練愛好者
• 力量訓練運動員
• 想要追蹤訓練進度的人
• 需要詳細數據分析的用戶

開始使用 WorkoutRecord，讓每次訓練都更有意義！
```

**關鍵詞** (100 字元):
```
健身,訓練,健身房,重訓,記錄,體重,三大項,深蹲,臥推,硬舉
```

**支援 URL**: 
```
https://your-website.com/support
```

**隱私權政策 URL** (必須):
```
https://your-website.com/privacy
```

### 截圖要求

**必須提供的尺寸**:
- 6.7" Display (iPhone 15 Pro Max): 1290 x 2796
- 6.5" Display (iPhone 11 Pro Max): 1284 x 2778
- 5.5" Display (iPhone 8 Plus): 1242 x 2208

**截圖數量**: 每個尺寸 3-10 張

**建議截圖內容**:
1. 首頁 Dashboard
2. 訓練中畫面
3. 數據統計圖表
4. 歷史記錄
5. 三大項進度

### App 預覽影片 (可選但建議)
- 15-30 秒
- 展示核心功能
- 突出 UI/UX

### 分類

**主要分類**: 健康與健身
**次要分類**: 生產力工具

### 年齡分級

建議: **4+** (適合所有年齡)

---

## 5️⃣ 環境配置

### EnvironmentConfig.swift

**需要更新的配置**:

```swift
// 生產環境 API URL (待替換)
static var apiBaseURL: String {
    switch current {
    case .debug:
        return "http://localhost:8080/api"
    case .production:
        return "https://api.your-domain.com/api"  // ⚠️ 替換為實際 URL
    }
}

// App Store URL (待替換)
static var appStoreURL: String {
    "https://apps.apple.com/app/id1234567890"  // ⚠️ 替換為實際 App ID
}
```

### VersionManager.swift

**Remote Config 預設值**:
```swift
let defaults: [String: NSObject] = [
    "ios_minimum_version": "1.0.0" as NSObject,
    "ios_latest_version": "1.0.0" as NSObject,
    "ios_force_update": false as NSObject,
    "ios_update_message_zh": "新版本包含重要更新和錯誤修復" as NSObject,
    "ios_update_url": "https://apps.apple.com/app/id" as NSObject  // ⚠️ 待替換
]
```

---

## 6️⃣ 測試清單

### 功能測試

- [ ] 登入流程
  - [ ] Apple ID 登入 (真實設備)
  - [ ] 模擬器測試登入
  - [ ] Firebase Auth 同步
  
- [ ] 新手引導
  - [ ] 隱私權同意頁面
  - [ ] 基本資料填寫 (體重必填)
  - [ ] 目標設定
  - [ ] 滑動導航
  
- [ ] 訓練功能
  - [ ] 開始訓練
  - [ ] 添加動作
  - [ ] 記錄組數
  - [ ] 休息計時器 (Header 模式)
  - [ ] 組間休息時間記錄
  - [ ] 完成訓練 (需完成所有動作)
  - [ ] 訓練報告
  
- [ ] 數據功能
  - [ ] 訓練容量趨勢
  - [ ] 個人紀錄
  - [ ] 三大項紀錄 (手動 + 系統估算)
  - [ ] 成就系統
  
- [ ] 設定功能
  - [ ] 重量單位切換 (kg/lb)
  - [ ] 主題切換
  - [ ] 個人資料編輯
  
- [ ] 版本管理
  - [ ] 版本檢查
  - [ ] 可選更新提示
  - [ ] 強制更新 (通過 Remote Config 測試)

### 性能測試

- [ ] App 啟動時間 < 2 秒
- [ ] 訓練記錄保存 < 1 秒
- [ ] 圖表渲染流暢
- [ ] 記憶體使用正常 (< 100MB)
- [ ] 電池消耗合理

### 相容性測試

- [ ] iOS 16.0+
- [ ] iPhone 型號
  - [ ] iPhone SE (小屏幕)
  - [ ] iPhone 14
  - [ ] iPhone 15 Pro Max (大屏幕)
- [ ] 深色/淺色模式
- [ ] 不同語系 (簡體中文/繁體中文)

### 離線測試

- [ ] 離線記錄訓練
- [ ] 離線瀏覽歷史
- [ ] 網路恢復後正常運作

---

## 7️⃣ 上架前最終檢查

### 代碼檢查

- [ ] 移除所有 `print()` 調試語句 (保留必要的 log)
- [ ] 移除所有 `TODO` 和 `FIXME` (或確保不影響核心功能)
- [ ] 移除測試代碼
- [ ] 確保沒有敏感信息洩露 (API keys, secrets)

### 資源檢查

- [ ] App Icon 已設置 (所有尺寸)
- [ ] Launch Screen 已設置
- [ ] 所有圖片資源已優化
- [ ] 未使用的資源已移除

### 文件檢查

- [ ] README.md 更新
- [ ] 隱私權政策準備
- [ ] 使用條款準備
- [ ] 支援頁面準備

### 版本號

- [ ] CFBundleShortVersionString: `1.0.0`
- [ ] CFBundleVersion: `1`

---

## 8️⃣ 提交流程

### 1. Archive

1. 選擇 **Any iOS Device (arm64)**
2. Product → Archive
3. 等待建置完成

### 2. Distribute

1. 選擇 Archive
2. Distribute App
3. 選擇 **App Store Connect**
4. 選擇 **Upload**
5. 配置選項:
   - ✅ Include bitcode (如適用)
   - ✅ Upload your app's symbols
   - ✅ Manage Version and Build Number
6. 上傳

### 3. TestFlight

1. 在 App Store Connect 選擇建置版本
2. 添加測試資訊
3. 提交內部測試
4. 邀請測試用戶
5. 收集反饋

### 4. App Store 審核

1. 準備審核信息
2. 填寫 App Review Information
3. 提供測試帳號 (如需要)
4. 提交審核
5. 等待審核結果 (通常 24-48 小時)

---

## 9️⃣ 上線後監控

### 監控指標

- [ ] 崩潰率 < 0.1%
- [ ] 用戶留存率
- [ ] 活躍用戶數 (DAU/MAU)
- [ ] 用戶反饋
- [ ] App Store 評分

### Firebase 監控

- [ ] Analytics 數據
- [ ] Crashlytics 崩潰報告
- [ ] Performance Monitoring

---

## 🔟 常見問題

### Q: 如何切換 Debug/Release 環境？

**A**: 
- **Debug**: Xcode → Edit Scheme → Run → Build Configuration: Debug
- **Release**: Xcode → Edit Scheme → Run → Build Configuration: Release
- **Archive**: 自動使用 Release 配置

### Q: Firebase 如何區分開發和生產環境？

**A**: 
1. 在 Firebase Console 創建兩個專案 (Development 和 Production)
2. 下載兩個 `GoogleService-Info.plist`
3. 開發時使用開發專案的配置
4. Archive 上架前替換為生產專案的配置

### Q: 如何測試強制更新？

**A**:
1. 在 Firebase Remote Config 設置:
   - `ios_minimum_version`: 設為高於當前版本 (如 `2.0.0`)
   - `ios_force_update`: `true`
2. 重新啟動 App
3. 應看到強制更新畫面

### Q: 模擬器無法測試 Apple Sign In 怎麼辦？

**A**: 
- 使用模擬器測試登入按鈕 (已實現)
- Apple Sign In 必須在真實設備測試
- TestFlight 測試時驗證完整流程

---

## ✅ 配置完成確認

完成所有配置後，在此打勾:

- [ ] Info.plist 已配置
- [ ] Firebase 已配置 (Development & Production)
- [ ] Xcode 專案已配置
- [ ] App Store Connect 已準備
- [ ] 環境配置已更新
- [ ] 所有測試已通過
- [ ] 代碼已清理
- [ ] 資源已優化
- [ ] 文件已準備
- [ ] 已成功 Archive
- [ ] TestFlight 測試完成
- [ ] 準備提交審核

---

**最後更新**: 2025-10-29
**負責人**: [Your Name]
**狀態**: 準備上線 🚀

