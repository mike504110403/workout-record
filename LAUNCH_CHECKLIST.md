# WorkoutRecord App 上線準備清單

## 📱 App Store Connect 設定

### 1. 創建 App
- [ ] 登入 [App Store Connect](https://appstoreconnect.apple.com)
- [ ] 點擊「我的 App」→「+」→「新增 App」
- [ ] 填寫基本資訊：
  - **平台**: iOS
  - **名稱**: WorkoutRecord (或你想要的名稱)
  - **主要語言**: 繁體中文
  - **Bundle ID**: 選擇你在 Xcode 中設定的 Bundle ID
  - **SKU**: 可以使用 `workout-record-2025` 或任意唯一標識符
  - **使用者權限**: 完整權限

### 2. App 資訊設定
- [ ] **類別**:
  - 主要類別: 健康與健身
  - 次要類別: 生活風格（選填）

- [ ] **年齡分級**: 4+（無限制內容）

- [ ] **隱私政策 URL**: 
  - 如果你有網站，放置隱私政策頁面 URL
  - 或使用 GitHub Pages 託管隱私政策

### 3. 定價與供應狀況
- [ ] **價格**: 免費（或設定價格）
- [ ] **供應地區**: 選擇要上架的國家/地區
  - 建議：台灣、香港、澳門、美國

### 4. App 資訊頁面
- [ ] **App 預覽和截圖**（必需）:
  - **6.7 吋顯示器** (iPhone 15 Pro Max): 至少 3 張，最多 10 張
    - 建議尺寸: 1290 x 2796 像素
  - **6.5 吋顯示器** (iPhone 14 Plus): 至少 3 張
    - 建議尺寸: 1242 x 2688 像素
  
  **截圖建議內容**:
  1. 訓練記錄頁面
  2. 數據統計頁面
  3. 訓練歷史頁面
  4. 三項力量訓練頁面
  5. 訓練進度圖表

- [ ] **宣傳文字**（選填，170 字元以內）:
  ```
  專業健身訓練記錄 App，精準追蹤你的每一次進步！
  ```

- [ ] **描述**（建議 1000-4000 字元）:
  ```
  WorkoutRecord 是一款專為健身愛好者設計的訓練記錄 App。

  核心功能：
  ✓ 訓練記錄 - 精準記錄每組重量、次數和休息時間
  ✓ 數據分析 - 視覺化圖表展示訓練進度和容量趨勢
  ✓ 個人記錄 - 自動追蹤並更新你的 PR（Personal Record）
  ✓ 經典三項 - 專門追蹤深蹲、臥推、硬舉的力量進步
  ✓ 自定義動作 - 支援添加任何訓練動作
  ✓ 訓練模板 - 快速開始常用訓練計畫
  ✓ 體重追蹤 - 記錄體重變化趨勢
  ✓ 訓練建議 - 智慧分析提供訓練優化建議

  特色：
  • 簡潔直覺的介面設計
  • 支援深色模式
  • 完全離線使用，數據本地存儲
  • Apple ID 快速登入
  • 隱私優先，不會上傳個人訓練數據

  適合對象：
  • 健身新手想要系統化記錄訓練
  • 進階訓練者追求精確數據分析
  • 力量訓練愛好者關注三大項進步
  • 任何想要科學化訓練的人

  下載 WorkoutRecord，開始你的科學訓練之旅！
  ```

- [ ] **關鍵字**（最多 100 字元，用逗號分隔）:
  ```
  健身,訓練,重訓,健身房,力量訓練,深蹲,臥推,硬舉,健身記錄,PR
  ```

- [ ] **支援 URL**: 你的支援網站或 GitHub Issues 頁面

- [ ] **行銷 URL**（選填）: 你的官方網站

### 5. App 隱私設定
- [ ] 填寫「App 隱私」問卷：
  
  **收集的數據類型**:
  - ✅ **使用者 ID** (用於 Apple ID 登入)
    - 用途: 身份識別、App 功能
    - 是否與使用者關聯: 是
    - 是否用於追蹤: 否
  
  - ✅ **健康與健身資料** (訓練記錄、體重)
    - 用途: App 功能
    - 是否與使用者關聯: 是
    - 是否用於追蹤: 否
  
  **數據使用說明**:
  - 所有訓練數據存儲在本地裝置
  - 僅記錄 Apple ID 用於身份識別
  - 不會將訓練數據上傳到伺服器
  - 不會與第三方分享數據

---

## 🔥 Firebase 設定

### 1. 創建 Firebase 專案
- [ ] 前往 [Firebase Console](https://console.firebase.google.com)
- [ ] 點擊「新增專案」
- [ ] 專案名稱: `workout-record` 或你想要的名稱
- [ ] 選擇是否啟用 Google Analytics（建議啟用）
- [ ] 建立專案

### 2. 新增 iOS App
- [ ] 在 Firebase 專案中點擊「新增應用程式」→ iOS
- [ ] 填寫資訊：
  - **Apple 套件 ID**: 你的 Bundle ID（例如：`com.yourname.WorkoutRecord`）
  - **App 暱稱**: WorkoutRecord
  - **App Store ID**: （暫時留空，上架後再填）

### 3. 下載設定檔
- [ ] 下載 `GoogleService-Info.plist`
- [ ] **重要**: 需要下載兩個版本
  - **Debug 版本** (開發用)
  - **Release 版本** (正式上線用)

### 4. 將設定檔加入專案

#### 方法 A: 使用環境切換（推薦）
```bash
# 創建兩個設定檔目錄
cd ios/WorkoutRecord/WorkoutRecord
mkdir -p Firebase/Debug
mkdir -p Firebase/Release

# 放置對應的 GoogleService-Info.plist
# Debug 版本 → Firebase/Debug/GoogleService-Info.plist
# Release 版本 → Firebase/Release/GoogleService-Info.plist
```

然後在 Xcode 中：
- [ ] Build Phases → 新增 Run Script
```bash
if [ "${CONFIGURATION}" == "Debug" ]; then
    cp "${PROJECT_DIR}/WorkoutRecord/Firebase/Debug/GoogleService-Info.plist" "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/GoogleService-Info.plist"
else
    cp "${PROJECT_DIR}/WorkoutRecord/Firebase/Release/GoogleService-Info.plist" "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/GoogleService-Info.plist"
fi
```

#### 方法 B: 簡單方式（只用一個設定檔）
- [ ] 直接將 `GoogleService-Info.plist` 拖入 Xcode 專案
- [ ] 確保勾選「Copy items if needed」和你的 Target

### 5. Firebase 功能設定

#### Authentication (使用者驗證)
- [ ] Firebase Console → Authentication → 開始使用
- [ ] 啟用登入方式：
  - ✅ **Apple** (必需)
    - 需要填寫：
      - Apple Team ID
      - 金鑰 ID
      - 私密金鑰檔案
    - 在 Apple Developer 中設定 Sign in with Apple

#### Analytics (分析)
- [ ] Firebase Console → Analytics
- [ ] 已自動啟用（如果創建專案時選擇了）
- [ ] 檢查事件是否正常記錄

#### Crashlytics (當機報告) - 選用但強烈建議
- [ ] Firebase Console → Crashlytics → 開始使用
- [ ] 按照指示在 Xcode 中設定：
  - Build Phases → 新增 Run Script
  ```bash
  "${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
  ```
  - 輸入檔案：`${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${TARGET_NAME}`

---

## 📄 Info.plist 設定

### 1. 必需的權限說明
在 `Info.plist` 中添加以下內容：

```xml
<!-- Apple ID 登入 -->
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.YOUR-CLIENT-ID</string>
        </array>
    </dict>
</array>

<!-- 隱私權限說明（如果未來要用到） -->
<key>NSCameraUsageDescription</key>
<string>用於拍攝訓練照片記錄</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>用於儲存和讀取訓練照片</string>

<!-- App Transport Security（允許 HTTP 連線，僅開發用） -->
<!-- 正式上線時應移除或限制 -->
```

### 2. 版本號設定
- [ ] **CFBundleShortVersionString** (Version): `1.0.0`
  - 這是顯示給用戶看的版本號
  - 每次更新都要改變（例如：1.0.1, 1.1.0, 2.0.0）

- [ ] **CFBundleVersion** (Build): `1`
  - 這是內部建置號碼
  - 每次上傳到 App Store Connect 都必須遞增
  - 可以是純數字（1, 2, 3...）

### 3. Bundle Identifier
- [ ] 確保與 Apple Developer 中設定的一致
- [ ] 格式：`com.yourname.WorkoutRecord`
- [ ] **注意**: 上線後無法更改！

### 4. Display Name
- [ ] **CFBundleDisplayName**: 在手機桌面顯示的名稱
- [ ] 建議：`WorkoutRecord` 或 `訓練記錄`
- [ ] 限制：最多 10-12 個字元（依語言而異）

---

## 🔐 Apple Developer 設定

### 1. Identifiers (Bundle ID)
- [ ] 登入 [Apple Developer](https://developer.apple.com/account)
- [ ] Certificates, Identifiers & Profiles → Identifiers
- [ ] 點擊「+」新增 App ID
- [ ] 選擇 App IDs → Continue
- [ ] 填寫資訊：
  - Description: WorkoutRecord
  - Bundle ID: Explicit - `com.yourname.WorkoutRecord`
  - Capabilities:
    - ✅ Sign in with Apple
    - ✅ Push Notifications (如果未來要用)

### 2. Certificates (憑證)
- [ ] Distribution Certificate (發布憑證)
  - 用於上架 App Store
  - Certificates → 點擊「+」
  - 選擇「Apple Distribution」
  - 上傳 CSR (Certificate Signing Request)
    - 在 Mac 的「鑰匙圈存取」中生成

### 3. Provisioning Profiles (配置描述檔)
- [ ] App Store Profile
  - Profiles → 點擊「+」
  - 選擇「App Store」
  - 選擇你的 App ID
  - 選擇 Distribution Certificate
  - 命名：`WorkoutRecord App Store`
  - 下載並雙擊安裝

### 4. Sign in with Apple 設定
- [ ] Certificates, Identifiers & Profiles → Keys
- [ ] 點擊「+」創建新的 Key
- [ ] 勾選「Sign in with Apple」
- [ ] Configure → 選擇你的 App ID
- [ ] 下載金鑰檔案（.p8）
- [ ] **重要**: 記錄 Key ID，只能下載一次！

---

## 📦 Xcode 建置設定

### 1. Signing & Capabilities
- [ ] 選擇你的 Target → Signing & Capabilities
- [ ] **Automatically manage signing**: 建議勾選（簡化流程）
- [ ] Team: 選擇你的開發者帳號
- [ ] Bundle Identifier: 確認正確
- [ ] Capabilities:
  - [ ] Sign in with Apple
  - [ ] Push Notifications (如需要)

### 2. Build Settings
- [ ] **Deployment Target**: 設定最低支援的 iOS 版本
  - 建議：iOS 16.0 或更高

- [ ] **Bitcode**: NO (Apple 已不再需要)

- [ ] **Strip Debug Symbols During Copy**: YES (Release)

- [ ] **Optimization Level**: 
  - Debug: -Onone
  - Release: -O (最佳化)

### 3. Build Configuration
- [ ] 確保有兩個 Configuration:
  - **Debug**: 開發測試用
  - **Release**: 正式上架用

### 4. Archive 設定
- [ ] Product → Scheme → Edit Scheme
- [ ] Archive → Build Configuration: **Release**
- [ ] 確保 Archive 使用正確的設定

---

## 🚀 TestFlight 測試（建議）

### 1. 上傳第一個 Build
- [ ] Xcode → Product → Archive
- [ ] 等待建置完成
- [ ] Window → Organizer
- [ ] 選擇你的 Archive → Distribute App
- [ ] 選擇「App Store Connect」
- [ ] Upload

### 2. TestFlight 設定
- [ ] 登入 App Store Connect
- [ ] 進入你的 App → TestFlight
- [ ] 等待建置處理完成（約 5-15 分鐘）
- [ ] **合規資訊**:
  - 是否使用加密: 否（除非你有特殊加密功能）

### 3. 內部測試
- [ ] TestFlight → 內部測試 → 新增測試人員
- [ ] 邀請測試人員（最多 100 人）
- [ ] 測試人員下載 TestFlight App 即可測試

### 4. 外部測試（選用）
- [ ] 需要先通過 Beta App 審查
- [ ] 填寫測試資訊
- [ ] 提交審查（約 24 小時）

---

## ✅ 上架前檢查清單

### App 功能檢查
- [ ] 所有核心功能正常運作
- [ ] 沒有明顯的 Bug 或 Crash
- [ ] UI 在不同螢幕尺寸正常顯示
- [ ] 深色模式正常運作
- [ ] Apple ID 登入功能正常
- [ ] 數據存儲和讀取正常
- [ ] 所有文字正確無誤（無測試用文字）

### 合規檢查
- [ ] 隱私政策已準備
- [ ] 年齡分級正確
- [ ] 無侵權內容（圖片、文字、音樂等）
- [ ] 遵守 App Store 審查指南

### 提交資料準備
- [ ] App 截圖（至少 3 張）
- [ ] App 圖示（1024x1024px）
- [ ] 描述文字
- [ ] 關鍵字
- [ ] 支援 URL
- [ ] 隱私政策 URL

---

## 📤 提交審查

### 1. 準備提交
- [ ] App Store Connect → 你的 App
- [ ] 版本資訊 → 1.0.0
- [ ] 填寫所有必填欄位
- [ ] 選擇建置版本（Build）

### 2. 審查資訊
- [ ] **聯絡資訊**: 你的電子郵件和電話
- [ ] **審查備註**: 
  ```
  感謝審查團隊！
  
  測試帳號資訊：
  - 使用 Apple ID 登入即可
  - 無需額外設定
  
  主要功能：
  1. 訓練記錄
  2. 數據分析
  3. 個人記錄追蹤
  
  如有任何問題請隨時聯繫。
  ```

- [ ] **Demo 帳號**（如需要）:
  - 使用 Apple ID 登入，無需提供

### 3. 提交
- [ ] 最後檢查所有資訊
- [ ] 點擊「提交以供審查」
- [ ] 等待審查（通常 24-48 小時）

---

## 📊 審查狀態追蹤

### 可能的狀態
1. **等待審查** (Waiting for Review)
   - 排隊中，耐心等待

2. **審查中** (In Review)
   - 審查團隊正在測試你的 App

3. **需要更多資訊** (Metadata Rejected)
   - 需要修改截圖、描述等資訊
   - 修改後重新提交，不需要重新上傳建置

4. **被拒絕** (Rejected)
   - 仔細閱讀拒絕原因
   - 修正問題後重新提交
   - 常見原因：
     - 功能不完整
     - Crash 問題
     - 違反隱私政策
     - UI 問題

5. **準備銷售** (Ready for Sale)
   - 🎉 恭喜！App 已上架！

---

## 🎯 上架後

### 1. 監控
- [ ] 查看 App Store 評論
- [ ] Firebase Analytics 檢查使用數據
- [ ] Crashlytics 監控當機報告

### 2. 更新準備
- [ ] 版本號規劃
- [ ] 新功能開發
- [ ] Bug 修復

### 3. 推廣
- [ ] 社群媒體分享
- [ ] 請朋友評論
- [ ] 收集使用者回饋

---

## ⚠️ 重要提醒

1. **Bundle ID 無法更改**
   - 上線後就固定了，請務必確認正確

2. **版本號管理**
   - Version (CFBundleShortVersionString): 使用者看到的版本
   - Build (CFBundleVersion): 每次上傳必須遞增

3. **Firebase 設定檔安全**
   - 不要將 `GoogleService-Info.plist` 上傳到公開的 Git
   - 添加到 `.gitignore`

4. **審查時間**
   - 首次審查可能較久（2-3 天）
   - 更新審查通常較快（1-2 天）

5. **備份**
   - 保存好所有憑證和金鑰
   - 記錄 App Store Connect 帳號密碼

---

## 📞 遇到問題？

### Apple 相關
- [App Store 審查指南](https://developer.apple.com/app-store/review/guidelines/)
- [App Store Connect 說明](https://help.apple.com/app-store-connect/)

### Firebase 相關
- [Firebase iOS 文件](https://firebase.google.com/docs/ios/setup)
- [Firebase Console](https://console.firebase.google.com)

### 社群支援
- [Apple Developer Forums](https://developer.apple.com/forums/)
- Stack Overflow

---

**祝你上架順利！🚀**

