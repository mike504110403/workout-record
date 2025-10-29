# 🔧 App Store Connect 提交錯誤修正指南

## 📋 錯誤清單

### 錯誤 1: 無法新增以供審查
需要完成以下 5 個項目：

1. ❌ 上傳 13 吋 iPad 顯示器的截圖
2. ❌ 在「App 隱私權」中輸入隱私權政策 URL
3. ❌ 完成「App 隱私」設定
4. ❌ 處理 NSUserTrackingUsageDescription
5. ❌ 在「定價」區段選擇價格層級

### 錯誤 2: 本頁面有錯誤
1. ❌ 繁體中文 - 支援 URL - 此欄位為必填

---

## ✅ 解決方案 1: iPad 截圖

### 最簡單的方法：不支援 iPad

如果你的 App 只支援 iPhone：

#### 步驟 1: 檢查 Xcode 設定
1. 打開 Xcode 專案
2. 選擇 Target → WorkoutRecord
3. 點擊「General」標籤
4. 找到「Deployment Info」
5. 確認「Devices」設定為：
   ```
   ✅ iPhone（只勾選 iPhone）
   ❌ iPad（不勾選）
   ```

#### 步驟 2: 重新建置
如果修改了 Deployment Info，需要：
1. Product → Clean Build Folder (⇧⌘K)
2. Product → Archive
3. 重新上傳到 App Store Connect

#### 完成後
- iPad 截圖要求會自動消失
- 只需要 iPhone 截圖

---

### 如果你想支援 iPad

#### 在 Xcode 模擬器截圖：

1. **選擇 iPad Pro 13-inch 模擬器**
   ```
   在你的模擬器列表中應該有：
   - iPad Pro 13-inch (M4)
   ```

2. **執行 App** (⌘R)

3. **截圖** (⌘S)

4. **驗證尺寸**
   - iPad Pro 13-inch: 2048 × 2732 pixels

5. **上傳到 App Store Connect**
   - 在「13 吋 iPad 顯示器」欄位上傳

---

## ✅ 解決方案 2: 隱私權政策 URL

### 選項 A: 使用 GitHub Pages（推薦，免費）

#### 步驟：

1. **建立 GitHub Repository**
   ```bash
   # 如果還沒有 GitHub repo
   # 前往 https://github.com/new
   # 建立 public repository
   ```

2. **建立隱私權政策檔案**

創建檔案：`privacy.html`

```html
<!DOCTYPE html>
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>WorkitOut 隱私權政策</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            line-height: 1.6;
            max-width: 800px;
            margin: 40px auto;
            padding: 0 20px;
            color: #333;
        }
        h1 {
            color: #007AFF;
            border-bottom: 2px solid #007AFF;
            padding-bottom: 10px;
        }
        h2 {
            color: #555;
            margin-top: 30px;
        }
    </style>
</head>
<body>
    <h1>WorkitOut 隱私權政策</h1>
    <p><strong>最後更新：2025 年 10 月 29 日</strong></p>

    <h2>資料收集</h2>
    <p>WorkitOut 重視您的隱私。我們收集以下資料：</p>

    <h3>1. 使用者 ID</h3>
    <ul>
        <li><strong>來源</strong>：Apple Sign In</li>
        <li><strong>用途</strong>：身份驗證和 App 功能</li>
        <li><strong>儲存</strong>：僅用於登入驗證</li>
    </ul>

    <h3>2. 訓練數據</h3>
    <ul>
        <li><strong>儲存位置</strong>：僅在您的裝置上</li>
        <li><strong>不會上傳</strong>：所有訓練記錄僅本地儲存</li>
    </ul>

    <h3>3. 使用統計</h3>
    <ul>
        <li><strong>來源</strong>：Firebase Analytics</li>
        <li><strong>收集內容</strong>：匿名的使用情況數據</li>
        <li><strong>用途</strong>：改善 App 功能</li>
    </ul>

    <h2>資料使用</h2>
    <p>我們使用收集的資料用於：</p>
    <ul>
        <li>提供 App 核心功能</li>
        <li>改善使用者體驗</li>
        <li>分析 App 使用情況</li>
        <li>修復技術問題</li>
    </ul>

    <h2>資料安全</h2>
    <ul>
        <li>使用 Apple Sign In 保護帳號安全</li>
        <li>訓練數據僅本地儲存</li>
        <li>不與第三方分享個人訓練數據</li>
        <li>符合相關隱私法規</li>
    </ul>

    <h2>您的權利</h2>
    <p>您有權：</p>
    <ul>
        <li>查看您的資料</li>
        <li>刪除您的帳號</li>
        <li>停止使用 App</li>
    </ul>

    <h2>聯絡我們</h2>
    <p>如有任何隱私相關問題，請聯繫：<br>
    <a href="mailto:mike504110403@gmail.com">mike504110403@gmail.com</a></p>

    <h2>政策更新</h2>
    <p>我們可能會更新此隱私權政策。重大變更會在 App 內通知。</p>
</body>
</html>
```

3. **啟用 GitHub Pages**
   - 在 Repository 設定中
   - 找到「Pages」
   - 選擇 Source: main branch
   - 儲存

4. **取得 URL**
   ```
   https://yourusername.github.io/workitout/privacy.html
   ```

5. **填入 App Store Connect**
   ```
   App Store Connect → WorkitOut → App 資訊
   → 隱私權政策 URL → 貼上網址
   ```

---

### 選項 B: 使用 Notion（更簡單）

1. **建立 Notion 頁面**
   - 登入 Notion
   - 建立新頁面
   - 貼上隱私權政策內容

2. **設定為公開**
   - 點擊右上角「Share」
   - 選擇「Share to web」
   - 複製連結

3. **填入 App Store Connect**

---

### 選項 C: 暫時方案（不推薦）

如果真的來不及，可以暫時填寫：
```
https://example.com/privacy
```

但 Apple 審核時可能會要求提供有效連結。

---

## ✅ 解決方案 3: 完成 App 隱私設定

### 位置：
```
App Store Connect → WorkitOut → App 隱私
```

### 詳細步驟：
參考之前創建的 `PRIVACY_SETTINGS_GUIDE.md`

### 快速摘要：

1. **進入 App 隱私**
2. **選擇「是，我們會收集資料」**
3. **添加資料類型：**
   - 使用者 ID（Apple Sign In）
   - 產品互動（Firebase Analytics）
4. **填寫每個資料類型的用途**
5. **完成並發布**

---

## ✅ 解決方案 4: 處理 NSUserTrackingUsageDescription

### 問題：
你的 `Info.plist` 中有 `NSUserTrackingUsageDescription`，但可能不需要。

### 解決方法 A: 移除追蹤描述（推薦）

1. **打開 Info.plist**
   ```
   ios/WorkoutRecord/WorkoutRecord/Info.plist
   ```

2. **檢查是否有這個 Key**
   ```xml
   <key>NSUserTrackingUsageDescription</key>
   <string>此 App 會收集使用數據...</string>
   ```

3. **如果有，刪除這兩行**

4. **重新建置並上傳**

---

### 解決方法 B: 更新 App 隱私回應

如果你確實需要追蹤：

1. **在 App 隱私設定中**
2. **勾選「是，此 App 使用 IDFA」**
3. **說明追蹤用途**

**但你的 App 不需要追蹤！建議使用方法 A。**

---

## ✅ 解決方案 5: 設定價格

### 位置：
```
App Store Connect → WorkitOut → 定價與供應狀況
```

### 步驟：

1. **點擊「定價與供應狀況」**

2. **選擇價格**
   ```
   ✅ 免費（推薦）
   
   或
   
   選擇付費價格層級（例如：NT$ 30, NT$ 60）
   ```

3. **選擇供應國家/地區**
   ```
   ✅ 所有國家和地區
   
   或
   
   選擇特定國家
   ```

4. **儲存**

---

## ✅ 解決方案 6: 支援 URL

### 位置：
```
App Store Connect → WorkitOut → App 資訊
```

### 選項 A: 使用 GitHub（推薦）

創建一個簡單的支援頁面：

```html
<!DOCTYPE html>
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>WorkitOut 支援</title>
</head>
<body>
    <h1>WorkitOut 支援</h1>
    <p>如有任何問題，請聯繫：</p>
    <p>Email: <a href="mailto:mike504110403@gmail.com">mike504110403@gmail.com</a></p>
    
    <h2>常見問題</h2>
    <h3>如何記錄訓練？</h3>
    <p>點擊「訓練」標籤，選擇動作，開始記錄。</p>
    
    <h3>如何查看統計？</h3>
    <p>點擊「統計」標籤查看訓練容量和趨勢。</p>
</body>
</html>
```

URL: `https://yourusername.github.io/workitout/support.html`

---

### 選項 B: 使用 Email（簡單）

如果沒有網站，可以暫時填寫：
```
mailto:mike504110403@gmail.com
```

但建議還是提供網頁 URL。

---

## 📋 完整檢查清單

完成以下所有項目才能提交審核：

- [ ] **截圖**
  - [ ] iPhone 6.7" (至少 3 張)
  - [ ] iPad 13" (如果支援 iPad，至少 1 張)

- [ ] **隱私權**
  - [ ] 完成「App 隱私」設定
  - [ ] 提供隱私權政策 URL
  - [ ] 移除 NSUserTrackingUsageDescription（如果不需要）

- [ ] **定價**
  - [ ] 設定價格（免費或付費）
  - [ ] 選擇供應國家

- [ ] **支援資訊**
  - [ ] 提供支援 URL
  - [ ] 提供行銷 URL（選填）

- [ ] **文案**
  - [ ] App 名稱
  - [ ] 副標題
  - [ ] 描述
  - [ ] 關鍵字

- [ ] **審查資訊**
  - [ ] 聯絡資訊（姓名、電話、Email）
  - [ ] 附註說明

- [ ] **版權**
  - [ ] 填寫版權資訊

---

## 🎯 立即行動計畫

### 優先順序：

#### 1️⃣ **立即完成（必要）**
1. 設定定價（免費）
2. 提供支援 URL（暫時用 email）
3. 完成 App 隱私設定

#### 2️⃣ **稍後完成（建議）**
4. 建立隱私權政策網頁
5. 建立支援網頁

#### 3️⃣ **檢查並修正（如果需要）**
6. 移除 NSUserTrackingUsageDescription
7. 確認 iPad 支援設定

---

## 🆘 需要幫助？

如果在任何步驟遇到問題：
1. 截圖給我看
2. 告訴我卡在哪裡
3. 我會協助你解決

---

**讓我們一步步完成這些設定！** 🚀

