# Info.plist 和 Firebase 完整設定指南

## 🎯 當前狀態
- ✅ GoogleService-Info.plist 已存在
- ⚠️ 需要從 Firebase Console 下載完整的配置文件
- ⚠️ 需要在 Xcode 中添加 URL Scheme

---

## 📱 Step 1: 重新下載 GoogleService-Info.plist

### 為什麼需要重新下載？
當前的 `GoogleService-Info.plist` 缺少 `REVERSED_CLIENT_ID`，這是 Sign in with Apple 所需的關鍵配置。

### 如何下載：

1. **前往 Firebase Console**
   - 網址：https://console.firebase.google.com
   - 選擇專案：`work-it-out-6409d`

2. **進入專案設定**
   - 點擊左側齒輪圖示 ⚙️ → 「專案設定」
   - 找到「您的應用程式」區段
   - 找到 iOS 應用程式 `com.mikelin.workitout`

3. **下載配置文件**
   - 點擊「下載 GoogleService-Info.plist」按鈕
   - 下載完成後，**替換**現有的文件：
     ```
     ios/WorkoutRecord/WorkoutRecord/GoogleService-Info.plist
     ```

---

## 🔧 Step 2: 在 Xcode 中添加 URL Scheme

### 方法 A: 透過 Xcode UI（推薦）

1. **打開 Xcode**
   - 打開專案：`WorkoutRecord.xcodeproj`

2. **選擇 Target**
   - 在左側選擇「WorkoutRecord」專案
   - 選擇 `TARGETS` → `WorkoutRecord`

3. **進入 Info 頁籤**
   - 點擊頂部的「Info」標籤

4. **添加 URL Types**
   - 找到「URL Types」區塊
   - 如果沒有，點擊底部的「+」新增
   - 填入以下資訊：
     - **Identifier**: `com.googleusercontent.apps`
     - **URL Schemes**: `com.googleusercontent.apps.128440928271-175e9419fa9aa2c008fb7a` 
       （從新下載的 GoogleService-Info.plist 中的 REVERSED_CLIENT_ID 複製）
     - **Role**: `Editor`

---

## 🎯 Step 3: Firebase Console - Apple 登入設定

現在回到 Firebase Console 完成 Apple 登入設定：

### 1. 進入 Authentication
- Firebase Console → Authentication → 登入方式（Sign-in method）

### 2. 編輯 Apple 提供者
- 找到「Apple」，點擊編輯

### 3. 填入以下資訊：

```
✅ 啟用 Apple 登入

Services ID (OAuth code flow):
com.mikelin.workitout.signin

Apple 團隊 ID:
DDMW7327JC

金鑰 ID:
[從 Apple Developer 下載 .p8 時看到的 Key ID]

私密金鑰（.p8 檔案）:
[上傳剛才從 Apple Developer 下載的 .p8 檔案]
```

### 4. 點擊「儲存」

---

## ✅ Step 4: 驗證設定

### 檢查清單：

- [ ] 已從 Firebase Console 重新下載 `GoogleService-Info.plist`
- [ ] 新的 `GoogleService-Info.plist` 包含 `REVERSED_CLIENT_ID`
- [ ] 已在 Xcode 中添加 URL Scheme（使用 REVERSED_CLIENT_ID）
- [ ] 已在 Firebase Console 完成 Apple 登入設定
- [ ] 已上傳 .p8 私鑰檔案到 Firebase
- [ ] 已在 Apple Developer 完成 Services ID 設定
- [ ] Services ID 已設定 Return URL: `https://work-it-out-6409d.firebaseapp.com/__/auth/handler`

---

## 🚀 測試

完成以上設定後，你可以：

1. **在模擬器測試** (Debug 模式)
   ```bash
   cd ios/WorkoutRecord
   xcodebuild -scheme WorkoutRecord -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' build
   ```

2. **建置並上傳到 TestFlight** (Release 模式)
   - 在 Xcode 中選擇「Any iOS Device」
   - Product → Archive
   - 上傳到 App Store Connect

---

## 📝 Info.plist 最終應該包含的 Key（透過 Xcode 自動生成）

當你在 Xcode UI 中添加 URL Scheme 後，Xcode 會自動在生成的 Info.plist 中包含：

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.128440928271-xxxxx</string>
        </array>
    </dict>
</array>
```

---

## 🆘 常見問題

### Q: 為什麼需要 REVERSED_CLIENT_ID？
A: Firebase 使用這個 ID 來處理 OAuth 回調，讓 Apple Sign In 能夠正確運作。

### Q: URL Scheme 從哪裡來？
A: 從 Firebase Console 下載的 `GoogleService-Info.plist` 中的 `REVERSED_CLIENT_ID` 欄位。

### Q: 如果找不到 URL Types 怎麼辦？
A: 在 Xcode 的 Info 頁籤中，右鍵點擊空白處 → 選擇「Add Row」→ 選擇「URL types」。

---

## 📞 下一步

完成以上設定後：
1. 告訴我你已經完成哪些步驟
2. 如果遇到任何錯誤，提供截圖或錯誤訊息
3. 我會幫你驗證設定是否正確

