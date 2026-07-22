# Firebase 設定指南

## 📋 概述

本指南將說明如何設定 Firebase Firestore 以支援：
1. 使用者資料儲存（Apple ID 登入後的資訊）
2. 版本控制與強制更新機制

## 🔧 Firebase Console 設定步驟

### 1. 建立 Firestore 資料庫

1. 前往 [Firebase Console](https://console.firebase.google.com/)
2. 選擇您的專案 `WorkoutRecord`
3. 點擊左側選單的 **Firestore Database**
4. 點擊 **Create database**
5. 選擇 **Start in production mode**（稍後會設定安全規則）
6. 選擇資料庫位置（建議：`asia-east1` 台灣或 `asia-northeast1` 日本）

### 2. 設定 Firestore 安全規則

在 Firestore Database → Rules 頁面，替換為以下規則：

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // 使用者資料：只能讀寫自己的資料
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // 版本控制配置：所有人都可讀取
    match /app_config/version {
      allow read: if true;
      allow write: if false; // 只能透過 Firebase Console 手動更新
    }
    
    // Analytics 資料：已登入用戶可寫入
    match /analytics_sessions/{sessionId} {
      allow write: if request.auth != null;
      allow read: if false; // 只能透過後台查看
    }
    
    match /analytics_events/{eventId} {
      allow write: if request.auth != null;
      allow read: if false;
    }
    
    match /user_behavior/{behaviorId} {
      allow write: if request.auth != null;
      allow read: if false;
    }
  }
}
```

點擊 **Publish** 發布規則。

### 3. 建立版本控制文檔

在 Firestore Database → Data 頁面：

1. 建立 Collection：`app_config`
2. 在 `app_config` 中建立 Document，ID 設為：`version`
3. 新增以下欄位：

| 欄位名稱 | 類型 | 值 | 說明 |
|---------|------|-----|------|
| `latestVersion` | string | `1.0.0` | 最新版本號 |
| `minimumVersion` | string | `1.0.0` | 最低支援版本 |
| `forceUpdate` | boolean | `false` | 是否強制更新 |
| `updateMessage` | string | `發現新版本，請更新以獲得最佳體驗。` | 更新提示訊息 |

### 4. 設定 App Store ID

在 App 上架到 App Store 後：

1. 開啟檔案：`ios/WorkoutRecord/WorkoutRecord/Sources/Services/VersionCheckService.swift`
2. 找到以下兩處：
   ```swift
   let appStoreID = "YOUR_APP_STORE_ID"
   ```
3. 替換成您實際的 App Store ID（可在 App Store Connect 找到）

## 📱 如何觸發強制更新

當您要發布新版本並強制使用者更新時：

1. 在 Xcode 中更新版本號：
   - 選擇 Project → WorkoutRecord
   - General → Identity
   - 更新 **Version**（例如：1.0.0 → 1.1.0）
   - 更新 **Build**（例如：1 → 2）

2. 上架新版本到 App Store

3. 更新 Firebase 版本文檔：
   - 前往 Firebase Console → Firestore Database
   - 打開 `app_config/version` 文檔
   - 更新欄位：
     ```
     latestVersion: "1.1.0"
     minimumVersion: "1.1.0"  // 如果要強制更新舊版本
     forceUpdate: true         // 啟用強制更新
     updateMessage: "新版本已發布，請更新以繼續使用。"
     ```

## 🔄 版本更新流程

### 情境 1：建議更新（不強制）

設定：
```
latestVersion: "1.1.0"
minimumVersion: "1.0.0"
forceUpdate: false
```

結果：使用者打開 App 時會收到更新提示，但可以選擇繼續使用。

### 情境 2：強制更新

設定：
```
latestVersion: "1.1.0"
minimumVersion: "1.1.0"
forceUpdate: true
```

結果：使用者打開 App 時會看到強制更新畫面，無法繼續使用，必須前往 App Store 更新。

### 情境 3：部分強制更新

設定：
```
latestVersion: "1.2.0"
minimumVersion: "1.1.0"
forceUpdate: true
```

結果：
- 版本 < 1.1.0 的使用者：強制更新
- 版本 >= 1.1.0 的使用者：可以繼續使用

## 📊 資料庫結構

### users Collection

```json
{
  "userId": "001000.abc123def456.1234",
  "name": "張三",
  "email": "user@example.com",
  "createdAt": "2025-01-01T00:00:00Z",
  "updatedAt": "2025-01-01T00:00:00Z",
  "lastLoginAt": "2025-01-01T00:00:00Z"
}
```

### app_config/version Document

```json
{
  "latestVersion": "1.0.0",
  "minimumVersion": "1.0.0",
  "forceUpdate": false,
  "updateMessage": "發現新版本，請更新以獲得最佳體驗。"
}
```

### analytics_sessions Collection

```json
{
  "sessionId": "uuid-string",
  "startTime": "timestamp",
  "endTime": "timestamp",
  "duration": 300,
  "appVersion": "1.0.0",
  "deviceModel": "iPhone 15 Pro",
  "systemVersion": "17.6",
  "userId": "001000.abc123def456.1234",
  "pageVisits": {...},
  "pageDurations": {...},
  "buttonClicks": {...}
}
```

## 🧪 測試

### 測試強制更新功能

1. 在 Firebase Console 設定：
   ```
   latestVersion: "99.0.0"
   minimumVersion: "99.0.0"
   forceUpdate: true
   updateMessage: "測試強制更新訊息"
   ```

2. 重新開啟 App
3. 應該會看到強制更新畫面
4. 測試完後記得改回正確的版本號

### 測試使用者資料儲存

1. 登出並重新登入
2. 檢查 Firebase Console → Firestore Database → users
3. 應該可以看到新的使用者文檔

## ⚠️ 注意事項

1. **版本號格式**：必須使用語意化版本號（Semantic Versioning），例如：`1.0.0`
2. **App Store ID**：上架後才能取得，測試時會導向錯誤頁面是正常的
3. **安全規則**：不要將 write 權限設為 `true`，否則任何人都能修改版本設定
4. **測試環境**：建議使用 TestFlight 測試版本更新流程
5. **使用者體驗**：非必要不要使用強制更新，會影響使用者體驗

## 📞 問題排查

### 問題 1：使用者資料沒有儲存到 Firebase

檢查：
- Firebase 是否已初始化（檢查 Console 輸出）
- Firestore 安全規則是否正確
- 網路連線是否正常

### 問題 2：強制更新畫面沒有出現

檢查：
- Firebase 版本文檔是否存在
- 版本號格式是否正確
- `forceUpdate` 是否設為 `true`
- App 的當前版本是否低於 `minimumVersion`

### 問題 3：點擊更新按鈕沒反應

原因：App Store ID 尚未設定或不正確

解決：等待 App 上架後，更新 `VersionCheckService.swift` 中的 `appStoreID`

## 🎉 完成

設定完成後，您的 App 將擁有：
- ✅ 使用者資料儲存到 Firebase
- ✅ 版本檢查與強制更新機制
- ✅ 動態版本號顯示
- ✅ 點擊頁面關閉鍵盤功能
- ✅ iOS 17.6+ 相容性

---

最後更新：2025-10-31

