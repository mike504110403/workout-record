# 🚀 WorkoutRecord 快速上線指南

## 📋 5 分鐘快速檢查清單

### ✅ 第一步：Xcode 設定（5 分鐘）
```
1. 打開 Xcode 專案
2. 選擇 Target → Signing & Capabilities
   ✓ Team: 選擇你的 Apple Developer 帳號
   ✓ Bundle Identifier: 確認正確（例如：com.yourname.WorkoutRecord）
   ✓ Automatically manage signing: 勾選
   
3. 選擇 Target → Info
   ✓ Display Name: WorkoutRecord
   ✓ Version: 1.0.0
   ✓ Build: 1
```

### ✅ 第二步：Firebase 設定（10 分鐘）
```
1. 前往 https://console.firebase.google.com
2. 創建新專案 → "workout-record"
3. 添加 iOS App
   - Bundle ID: 填入你的 Bundle ID
   - 下載 GoogleService-Info.plist
4. 將 GoogleService-Info.plist 拖入 Xcode 專案
   - 勾選 "Copy items if needed"
   - 勾選你的 Target
5. 啟用 Authentication → Apple 登入
```

### ✅ 第三步：Apple Developer（15 分鐘）
```
1. 登入 https://developer.apple.com/account
2. Certificates, Identifiers & Profiles → Identifiers
   - 新增 App ID
   - Bundle ID: com.yourname.WorkoutRecord
   - Capabilities: ✓ Sign in with Apple
   
3. Certificates → 新增 Distribution Certificate
   - 從鑰匙圈存取生成 CSR
   - 上傳並下載憑證
   
4. Provisioning Profiles → 新增 App Store Profile
   - 選擇你的 App ID
   - 選擇 Distribution Certificate
   - 下載並安裝
```

### ✅ 第四步：App Store Connect（20 分鐘）
```
1. 登入 https://appstoreconnect.apple.com
2. 我的 App → + → 新增 App
   - 名稱: WorkoutRecord
   - 主要語言: 繁體中文
   - Bundle ID: 選擇你註冊的
   - SKU: workout-record-2025
   
3. 準備素材：
   📱 截圖（至少 3 張）:
      - 訓練記錄畫面
      - 數據統計畫面  
      - 歷史記錄畫面
   
   🎨 App 圖示（1024x1024px）
   
   📝 描述文字：
   """
   WorkoutRecord 是專為健身愛好者設計的訓練記錄 App
   
   核心功能：
   ✓ 訓練記錄 - 精準追蹤重量、次數、休息時間
   ✓ 數據分析 - 視覺化圖表展示進度
   ✓ 個人記錄 - 自動追蹤 PR
   ✓ 經典三項 - 深蹲、臥推、硬舉專項追蹤
   ✓ 自定義動作 - 支援任何訓練動作
   ✓ 訓練模板 - 快速開始常用計畫
   
   開始科學化訓練，記錄每一次進步！
   """
   
   🔍 關鍵字：
   健身,訓練,重訓,健身房,力量訓練,深蹲,臥推,硬舉
   
4. App 隱私：
   ✓ 使用者 ID（Apple ID 登入）
   ✓ 健康與健身（訓練記錄）
   ✓ 所有數據本地存儲
```

### ✅ 第五步：建置和上傳（10 分鐘）
```
1. Xcode → Product → Clean Build Folder
2. Xcode → Product → Archive
3. 等待建置完成
4. Window → Organizer
5. 選擇 Archive → Distribute App
6. 選擇 "App Store Connect"
7. Upload
8. 等待處理完成（5-15 分鐘）
```

### ✅ 第六步：TestFlight 測試（建議，1 天）
```
1. App Store Connect → TestFlight
2. 等待建置處理完成
3. 內部測試 → 新增測試人員
4. 測試 App 功能
5. 修正問題（如有）
```

### ✅ 第七步：提交審查（5 分鐘）
```
1. App Store Connect → 你的 App
2. + 版本 → 1.0.0
3. 選擇建置版本
4. 填寫所有資訊
5. 提交以供審查
6. 等待 24-48 小時
```

---

## 🎯 最關鍵的三件事

### 1. Bundle ID 必須一致
```
Xcode 中的 Bundle ID
= Apple Developer 中註冊的 App ID
= App Store Connect 中選擇的 Bundle ID
= Firebase 中設定的 Bundle ID

例如: com.yourname.WorkoutRecord
```

### 2. 版本號管理
```
CFBundleShortVersionString (Version): 1.0.0
- 給用戶看的版本號
- 每次更新要改（1.0.1, 1.1.0, 2.0.0）

CFBundleVersion (Build): 1
- 內部建置號碼
- 每次上傳必須遞增（1, 2, 3, 4...）
```

### 3. Firebase 設定檔位置
```
正確的位置：
ios/WorkoutRecord/WorkoutRecord/GoogleService-Info.plist

確保：
✓ 在 Xcode 專案導航器中可以看到
✓ Target Membership 勾選了 WorkoutRecord
✓ Copy Bundle Resources 中有這個檔案
```

---

## ⚡ 緊急處理指南

### 建置失敗
```
1. Product → Clean Build Folder
2. 關閉 Xcode
3. 刪除 DerivedData:
   rm -rf ~/Library/Developer/Xcode/DerivedData
4. 重新打開 Xcode
5. 重新建置
```

### 上傳失敗
```
1. 檢查 Bundle ID 是否正確
2. 檢查 Version 和 Build 號碼
3. 檢查簽章設定
4. 嘗試重新 Archive
```

### 審查被拒
```
1. 仔細閱讀拒絕原因
2. 修正問題
3. 回覆解決方案說明
4. 重新提交

常見原因：
- 功能不完整或有 Bug
- 截圖與實際不符
- 缺少隱私政策
- 違反審查指南
```

---

## 📞 需要幫助？

### Apple 官方資源
- App Store Connect 幫助: https://help.apple.com/app-store-connect/
- 審查指南: https://developer.apple.com/app-store/review/guidelines/
- 開發者論壇: https://developer.apple.com/forums/

### Firebase 資源
- Firebase 文件: https://firebase.google.com/docs/ios/setup
- Firebase Console: https://console.firebase.google.com

### 社群
- Stack Overflow
- Reddit r/iOSProgramming
- Twitter #iOSDev

---

## 🎉 上線後

### 第一週
- [ ] 每天檢查評論
- [ ] 監控 Crashlytics
- [ ] 收集使用者回饋
- [ ] 準備小更新修正 Bug

### 第一個月
- [ ] 分析使用數據（Firebase Analytics）
- [ ] 規劃新功能
- [ ] 準備 1.1.0 更新

---

**祝你上線順利！有問題隨時問我！** 🚀💪

