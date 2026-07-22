# Firebase 資料儲存調試指南

## 檢查 Firebase 資料的步驟

### 1. 在 Firebase Console 查看資料

1. 開啟 [Firebase Console](https://console.firebase.google.com/)
2. 選擇你的專案
3. 左側選單點擊 **Firestore Database**
4. 查看 `users` collection
5. 應該會看到以 Apple ID 為文檔 ID 的用戶資料

### 2. 檢查 Xcode Console 日誌

登入時應該會看到以下日誌：

```
🔄 開始同步到 Firebase...
   UserID: xxxxx
   Name: 用戶名稱
   Email: email@example.com
   Firebase 實例已取得
   準備寫入資料: [...]
   ✅ Firestore 寫入成功
✅ 用戶資料已同步到 Firebase Firestore
```

如果沒有看到這些日誌，或看到錯誤訊息，請檢查：

### 3. 常見問題排查

#### 問題 1: 看到 "❌ Firebase 同步失敗"

**可能原因：**
- Firebase 未正確初始化
- Firestore 規則設定錯誤
- 網路連接問題

**解決方案：**
1. 確認 `GoogleService-Info.plist` 已正確添加到專案
2. 確認 Firebase 已在 `WorkoutRecordApp.swift` 初始化
3. 檢查 Firestore 規則（見下方）

#### 問題 2: Firebase Console 看不到資料

**可能原因：**
- 資料寫入失敗但沒有錯誤（罕見）
- 看錯 Firebase 專案

**解決方案：**
1. 確認你在正確的 Firebase 專案
2. 重新登入 App 並觀察 Xcode Console
3. 檢查 Firestore 規則

#### 問題 3: 個人資料頁面沒有顯示資料

**說明：**
個人資料頁面顯示的是 **Apple ID 的姓名和電子郵件**，這些資訊來自：
- 首次登入時 Apple 提供的資訊
- 儲存在 UserDefaults 中
- 顯示在「帳號資訊」區塊

**注意：**
- Apple ID 只在**第一次登入**時提供姓名和電子郵件
- 如果是測試用戶重新登入，Apple 不會再次提供這些資訊
- 「基本資料」區塊的資料需要手動填寫

### 4. Firestore 規則設定

確認你的 Firestore 規則允許寫入：

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // 允許用戶讀寫自己的資料
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // 允許 app_config 讀取（用於版本檢查）
    match /app_config/{document=**} {
      allow read: if true;
      allow write: if false;
    }
  }
}
```

### 5. 測試建議

#### 完全重置測試：

1. **刪除 App**
2. **前往 Apple ID 設定**：
   - 設定 > Apple ID > 密碼與安全性 > 使用 Apple ID 的 App
   - 找到你的 App，選擇「停止使用 Apple ID」
3. **重新安裝 App**
4. **重新登入**
5. **觀察 Xcode Console 日誌**
6. **檢查 Firebase Console**

#### 模擬器測試：
- 模擬器會使用測試用戶 ID
- 仍然會同步到 Firebase
- 可以在 Firebase Console 看到 `simulator-test-user-xxx` 的資料

### 6. 確認資料已儲存

在 Firebase Console 的 Firestore 中，你應該看到：

```
users (collection)
  └── [Apple User ID] (document)
      ├── userId: "xxxxx"
      ├── name: "用戶名稱"
      ├── email: "email@example.com"
      ├── createdAt: Timestamp
      ├── updatedAt: Timestamp
      └── lastLoginAt: Timestamp
```

### 7. 如果仍然有問題

請提供以下資訊：
1. Xcode Console 的完整日誌
2. Firebase Console 的截圖
3. 個人資料頁面的截圖
4. 是真機還是模擬器測試
5. 是第一次登入還是重複登入

---

## 快速檢查清單

- [ ] Firebase Console 能開啟並看到專案
- [ ] Firestore Database 已啟用
- [ ] `GoogleService-Info.plist` 已添加到專案
- [ ] App 能正常編譯運行
- [ ] 登入時 Xcode Console 有 "🔄 開始同步到 Firebase..." 訊息
- [ ] 沒有看到 "❌ Firebase 同步失敗" 錯誤
- [ ] Firebase Console > Firestore 中能看到 `users` collection
- [ ] 個人資料頁面顯示 Apple ID 姓名和電子郵件

