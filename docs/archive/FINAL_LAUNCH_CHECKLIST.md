# 🚀 WorkoutRecord 上線前最終檢查清單

## ✅ 已完成項目

### 1. Apple Developer 設定
- ✅ App ID: `com.mikelin.workitout`
- ✅ Services ID: `com.mikelin.workitout.signin`
- ✅ Sign in with Apple 已啟用
- ✅ Return URL 已設定: `https://work-it-out-6409d.firebaseapp.com/__/auth/handler`
- ✅ Authentication Key (.p8) 已建立並下載

### 2. Firebase 設定
- ✅ Firebase 專案: `work-it-out-6409d`
- ✅ iOS App 已註冊: `com.mikelin.workitout`
- ✅ Authentication - Apple 登入已啟用
- ✅ Services ID、Team ID、Key ID、.p8 已設定
- ✅ Analytics 已設定

### 3. Xcode 專案設定
- ✅ GoogleService-Info.plist 已配置（包含 REVERSED_CLIENT_ID）
- ✅ Info.plist 已建立並配置 URL Scheme
- ✅ Firebase SDK 已整合
- ✅ Bundle ID: `com.mikelin.workitout`
- ✅ Team ID: `DDMW7327JC`
- ✅ Version: 1.0 (Build 10)
- ✅ 建置成功驗證 ✅

---

## 🧪 測試項目

### 在模擬器測試（Debug 模式）
- [ ] App 啟動正常
- [ ] 隱私權同意頁面正常顯示
- [ ] 新手引導流程正常
- [ ] Apple Sign In 登入流程正常
- [ ] 訓練記錄功能正常
- [ ] 歷史記錄查看正常
- [ ] 統計圖表顯示正常
- [ ] 三項記錄功能正常
- [ ] 設定頁面功能正常

### 在真機測試（Release 模式）
- [ ] 下載 TestFlight 版本
- [ ] 在真機上測試所有核心功能
- [ ] 確認 Apple Sign In 在真機上正常運作
- [ ] 檢查效能（載入速度、流暢度）
- [ ] 測試各種裝置尺寸（iPhone SE、標準、Plus/Max）
- [ ] 測試橫向和直向顯示

---

## 📱 App Store Connect 設定

### App 資訊
- [ ] App 名稱：WorkoutRecord（或你的中文名稱）
- [ ] 副標題（選填）
- [ ] 隱私權政策 URL
- [ ] App 類別：健康與健身
- [ ] 內容分級

### App 預覽和截圖
準備以下尺寸的截圖：
- [ ] 6.7" (iPhone 15 Pro Max): 1320 x 2868 px（必要）
- [ ] 6.5" (iPhone 11 Pro Max): 1284 x 2778 px
- [ ] 5.5" (iPhone 8 Plus): 1242 x 2208 px

建議準備 3-5 張截圖，展示：
1. 訓練記錄畫面
2. 統計圖表
3. 三項紀錄
4. 歷史紀錄
5. 新手引導

### App 描述
準備：
- [ ] 簡短描述（170 字以內）
- [ ] 完整描述
- [ ] 關鍵字（100 字以內，用逗號分隔）
- [ ] 推廣文字（選填）

### 版本資訊
- [ ] 版本號：1.0
- [ ] 版本更新說明

### App 審核資訊
- [ ] 聯絡資訊（姓名、電話、Email）
- [ ] 測試帳號資訊（如果需要登入）
- [ ] 附註說明（選填）

### 隱私權資訊
需要聲明的資料收集項目：
- [ ] 使用者 ID（Apple ID）
- [ ] 訓練數據（僅本地儲存 30 天）
- [ ] 使用情況數據（Firebase Analytics）
- [ ] 診斷數據（Firebase Crashlytics）

---

## 🔐 隱私權和安全

### Info.plist 隱私權描述
已設定：
- ✅ `NSUserTrackingUsageDescription`：用於 Firebase Analytics

### 資料安全
- ✅ 用戶資料本地儲存 30 天
- ✅ Apple Sign In 用於身份驗證
- ✅ Firebase 僅記錄登入事件和 UI 互動
- ✅ 訓練數據不上傳至 Firebase（免費用戶）

---

## 📋 上傳到 TestFlight 流程

### 步驟 1: 建立 Archive
1. 在 Xcode 中選擇 **Any iOS Device**
2. **Product** → **Clean Build Folder** (⇧⌘K)
3. **Product** → **Archive** (⌘B)
4. 等待 Archive 完成

### 步驟 2: 上傳
1. Archive 完成後會自動打開 **Organizer**
2. 選擇最新的 Archive
3. 點擊 **Distribute App**
4. 選擇 **App Store Connect**
5. 點擊 **Upload**
6. 選擇簽名方式：**Automatically manage signing**
7. 點擊 **Upload**

### 步驟 3: TestFlight 設定
1. 前往 App Store Connect
2. 選擇你的 App
3. 進入 **TestFlight** 標籤
4. 等待構建版本處理完成（通常 10-30 分鐘）
5. 填寫「測試資訊」和「出口合規性資訊」
6. 添加測試人員（內部測試或外部測試）

---

## 🎯 提交審核前檢查

### 技術要求
- ✅ App 在所有支援的裝置上正常運行
- ✅ 沒有崩潰或主要 Bug
- ✅ 所有功能都能正常使用
- ✅ 載入時間合理
- ✅ 使用者介面符合 Apple 設計規範

### 內容要求
- [ ] App 功能與描述相符
- [ ] 沒有誤導性內容
- [ ] 所有文字正確無誤
- [ ] 圖片和圖示質量良好

### 法律要求
- [ ] 隱私權政策已準備並可訪問
- [ ] 使用條款（如果需要）
- [ ] 資料收集已正確聲明
- [ ] 未使用未經授權的內容

---

## 📞 常見問題

### Q: Apple Sign In 在模擬器上測試失敗？
A: 確保：
1. 模擬器已登入 Apple ID（設定 → Apple ID）
2. Firebase Console 的 Apple 設定正確
3. URL Scheme 正確配置

### Q: 上傳失敗顯示「無效的簽名」？
A: 
1. 確認 Team ID 正確
2. 在 Xcode 中重新選擇 Team
3. 使用 **Automatically manage signing**

### Q: TestFlight 構建版本一直在處理中？
A: 通常需要 10-30 分鐘，如果超過 1 小時：
1. 檢查 Email 是否有錯誤通知
2. 確認 Info.plist 設定正確
3. 重新上傳

### Q: 審核被拒絕？
A: 常見原因：
1. 隱私權政策不完整
2. 功能描述不清楚
3. 測試帳號無法使用
4. App 崩潰或有重大 Bug

---

## 🎉 上線後

### 監控
- 使用 Firebase Console 監控：
  - 用戶登入數量
  - UI 互動事件
  - 崩潰報告（如果有）

### 更新
- 修復 Bug
- 添加新功能
- 更新版本號
- 重複 Archive 和上傳流程

---

## ✅ 最終確認

在提交審核前，請確認：
- [ ] 所有測試項目已通過
- [ ] TestFlight 測試完成
- [ ] App Store Connect 資訊完整
- [ ] 截圖和描述已準備
- [ ] 隱私權政策已發布
- [ ] 審核聯絡資訊正確

---

**準備好了就可以提交審核！🚀**
**預計審核時間：1-3 天**

Good luck! 🍀

