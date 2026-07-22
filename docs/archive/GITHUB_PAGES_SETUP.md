# 📄 GitHub Pages 完整設定指南

## 🎯 目標
建立免費的隱私權政策和支援頁面，讓 App Store Connect 可以使用。

---

## 📋 步驟 1: 建立 GitHub Repository

### 1️⃣ 登入 GitHub
- 前往：https://github.com
- 如果沒有帳號，點擊「Sign up」註冊
- 如果有帳號，點擊「Sign in」登入

### 2️⃣ 建立新的 Repository
1. 登入後，點擊右上角的「+」→ 「New repository」
2. 或直接前往：https://github.com/new

### 3️⃣ 填寫 Repository 資訊

```
Repository name: workitout-privacy
Description: WorkitOut App 隱私權政策和支援頁面
```

**重要設定：**
- ✅ **Public**（必須是公開的，GitHub Pages 才能運作）
- ☑ **Add a README file**（可勾選，方便一點）
- ⚪ 其他選項可以不勾選

### 4️⃣ 點擊「Create repository」

---

## 📋 步驟 2: 上傳隱私權政策檔案

### 方法 A: 透過 GitHub 網頁介面（最簡單）

#### 1️⃣ 建立 privacy.html

1. 在你剛建立的 Repository 頁面
2. 點擊「Add file」→ 「Create new file」
3. 檔案名稱輸入：`privacy.html`
4. 在編輯區貼上以下內容：

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
            background-color: #f5f5f7;
        }
        .container {
            background: white;
            padding: 40px;
            border-radius: 12px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #007AFF;
            border-bottom: 2px solid #007AFF;
            padding-bottom: 10px;
            font-size: 2em;
        }
        h2 {
            color: #555;
            margin-top: 30px;
            font-size: 1.5em;
        }
        h3 {
            color: #666;
            margin-top: 20px;
            font-size: 1.2em;
        }
        ul {
            line-height: 1.8;
        }
        a {
            color: #007AFF;
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
        .update-date {
            color: #888;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>WorkitOut 隱私權政策</h1>
        <p class="update-date"><strong>最後更新：2025 年 10 月 29 日</strong></p>

        <h2>概述</h2>
        <p>WorkitOut（以下簡稱「本 App」）重視您的隱私。本隱私權政策說明我們如何收集、使用和保護您的個人資訊。</p>

        <h2>資料收集</h2>
        <p>本 App 收集以下類型的資料：</p>

        <h3>1. 使用者身份識別資訊</h3>
        <ul>
            <li><strong>來源</strong>：Apple Sign In</li>
            <li><strong>收集內容</strong>：Apple ID、使用者識別碼</li>
            <li><strong>用途</strong>：身份驗證、提供 App 功能</li>
            <li><strong>儲存方式</strong>：安全加密儲存，僅用於登入驗證</li>
        </ul>

        <h3>2. 訓練數據</h3>
        <ul>
            <li><strong>收集內容</strong>：訓練記錄、體重記錄、個人紀錄</li>
            <li><strong>儲存位置</strong>：僅儲存在您的裝置上</li>
            <li><strong>重要說明</strong>：所有訓練數據不會上傳到任何伺服器</li>
        </ul>

        <h3>3. 使用統計資料</h3>
        <ul>
            <li><strong>來源</strong>：Firebase Analytics</li>
            <li><strong>收集內容</strong>：匿名的 App 使用情況（如頁面瀏覽、功能使用）</li>
            <li><strong>用途</strong>：改善 App 功能和使用者體驗</li>
            <li><strong>特性</strong>：完全匿名，不與個人身份連結</li>
        </ul>

        <h3>4. 診斷資料（如有）</h3>
        <ul>
            <li><strong>來源</strong>：Firebase Crashlytics</li>
            <li><strong>收集內容</strong>：崩潰報告、效能數據</li>
            <li><strong>用途</strong>：修復技術問題、提升 App 穩定性</li>
            <li><strong>特性</strong>：匿名收集</li>
        </ul>

        <h2>資料使用</h2>
        <p>我們使用收集的資料用於以下目的：</p>
        <ul>
            <li>提供核心 App 功能（訓練記錄、數據分析）</li>
            <li>維護和改善 App 效能</li>
            <li>分析使用情況以優化功能</li>
            <li>修復技術問題和 Bug</li>
            <li>提供客戶支援</li>
        </ul>

        <h2>資料分享</h2>
        <p>我們<strong>不會</strong>將您的個人訓練數據分享給第三方。</p>
        
        <h3>第三方服務</h3>
        <p>本 App 使用以下第三方服務：</p>
        <ul>
            <li><strong>Apple Sign In</strong>：用於安全登入</li>
            <li><strong>Firebase Analytics</strong>：用於匿名使用統計</li>
            <li><strong>Firebase Crashlytics</strong>：用於錯誤報告</li>
        </ul>
        <p>這些服務僅收集匿名或最少必要的資訊，並遵守其各自的隱私政策。</p>

        <h2>資料安全</h2>
        <p>我們採取以下措施保護您的資料：</p>
        <ul>
            <li>使用 Apple Sign In 提供業界標準的身份驗證</li>
            <li>訓練數據僅儲存在您的裝置本地</li>
            <li>使用加密技術保護資料傳輸</li>
            <li>不儲存敏感的個人財務資訊</li>
            <li>符合 Apple 的隱私和安全標準</li>
        </ul>

        <h2>資料保留</h2>
        <ul>
            <li><strong>訓練數據</strong>：保留在您的裝置上，直到您刪除 App 或手動清除</li>
            <li><strong>帳號資訊</strong>：在您使用 App 期間保留</li>
            <li><strong>匿名統計</strong>：按照 Firebase 的資料保留政策處理</li>
        </ul>

        <h2>您的權利</h2>
        <p>您對自己的資料擁有以下權利：</p>
        <ul>
            <li><strong>存取權</strong>：查看您的訓練數據（在 App 內隨時可查看）</li>
            <li><strong>刪除權</strong>：刪除您的帳號和所有相關數據</li>
            <li><strong>停止使用</strong>：隨時可以停止使用本 App</li>
            <li><strong>資料匯出</strong>：您可以截圖或記錄您的訓練數據</li>
        </ul>

        <h2>兒童隱私</h2>
        <p>本 App 適合所有年齡使用。我們不會有意收集 13 歲以下兒童的個人資訊。</p>

        <h2>隱私政策更新</h2>
        <p>我們可能會不時更新本隱私權政策。重大變更會透過以下方式通知您：</p>
        <ul>
            <li>在 App 內顯示通知</li>
            <li>更新本頁面的「最後更新」日期</li>
        </ul>
        <p>建議您定期查看本政策以了解最新資訊。</p>

        <h2>聯絡我們</h2>
        <p>如果您對本隱私權政策有任何疑問或建議，請透過以下方式聯繫我們：</p>
        <ul>
            <li><strong>電子郵件</strong>：<a href="mailto:mike504110403@gmail.com">mike504110403@gmail.com</a></li>
        </ul>
        <p>我們會在收到您的訊息後儘快回覆。</p>

        <h2>適用法律</h2>
        <p>本隱私權政策受中華民國法律管轄。我們致力於遵守相關的資料保護法規。</p>

        <hr style="margin: 40px 0; border: none; border-top: 1px solid #ddd;">

        <p style="text-align: center; color: #888; font-size: 0.9em;">
            © 2025 WorkitOut. All rights reserved.
        </p>
    </div>
</body>
</html>
```

5. 向下捲動，點擊「Commit changes」
6. 在彈出視窗中，直接點擊「Commit changes」確認

#### 2️⃣ 建立 support.html（支援頁面）

1. 回到 Repository 首頁
2. 再次點擊「Add file」→ 「Create new file」
3. 檔案名稱輸入：`support.html`
4. 貼上以下內容：

```html
<!DOCTYPE html>
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>WorkitOut 支援</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            line-height: 1.6;
            max-width: 800px;
            margin: 40px auto;
            padding: 0 20px;
            color: #333;
            background-color: #f5f5f7;
        }
        .container {
            background: white;
            padding: 40px;
            border-radius: 12px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
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
        h3 {
            color: #666;
            margin-top: 20px;
        }
        .faq-item {
            background: #f9f9f9;
            padding: 20px;
            margin: 20px 0;
            border-radius: 8px;
            border-left: 4px solid #007AFF;
        }
        a {
            color: #007AFF;
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
        .contact-box {
            background: #e8f4fd;
            padding: 20px;
            border-radius: 8px;
            margin: 20px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>WorkitOut 支援中心</h1>
        <p>歡迎來到 WorkitOut 支援頁面！如果您有任何問題或需要協助，請參考以下資訊。</p>

        <div class="contact-box">
            <h2>📧 聯絡我們</h2>
            <p>如有任何問題，請聯繫：</p>
            <p><strong>Email:</strong> <a href="mailto:mike504110403@gmail.com">mike504110403@gmail.com</a></p>
            <p>我們通常會在 24-48 小時內回覆您的訊息。</p>
        </div>

        <h2>❓ 常見問題</h2>

        <div class="faq-item">
            <h3>如何開始記錄訓練？</h3>
            <p>1. 點擊底部「訓練」標籤<br>
            2. 點擊「開始訓練」按鈕<br>
            3. 選擇訓練模板或自訂動作<br>
            4. 開始記錄每組的重量和次數</p>
        </div>

        <div class="faq-item">
            <h3>如何查看訓練統計？</h3>
            <p>點擊底部「數據」標籤，可以查看：<br>
            - 訓練容量趨勢<br>
            - 肌群訓練分布<br>
            - 個人紀錄（PR）<br>
            - 三大項記錄</p>
        </div>

        <div class="faq-item">
            <h3>如何自訂動作？</h3>
            <p>在訓練頁面中：<br>
            1. 點擊「選擇動作」<br>
            2. 滑到底部點擊「自訂動作」<br>
            3. 輸入動作名稱和選擇主要肌群<br>
            4. 儲存後即可使用</p>
        </div>

        <div class="faq-item">
            <h3>資料會同步到雲端嗎？</h3>
            <p>目前所有訓練數據僅儲存在您的裝置上，不會上傳到雲端。這確保了您的隱私和資料安全。</p>
        </div>

        <div class="faq-item">
            <h3>如何記錄體重？</h3>
            <p>1. 點擊首頁的「記錄體重」卡片<br>
            2. 輸入當前體重<br>
            3. 點擊儲存<br>
            您可以在「數據」→「體重」標籤中查看體重變化趨勢。</p>
        </div>

        <div class="faq-item">
            <h3>如何使用訓練模板？</h3>
            <p>訓練模板讓您快速開始常用的訓練組合：<br>
            1. 在訓練頁面選擇「模板」<br>
            2. 選擇預設模板（如：胸部訓練、腿部訓練）<br>
            3. 或建立自己的訓練模板<br>
            4. 一鍵啟動訓練</p>
        </div>

        <h2>🔧 技術支援</h2>

        <div class="faq-item">
            <h3>App 無法開啟或閃退</h3>
            <p>1. 嘗試重新啟動 App<br>
            2. 重新啟動您的裝置<br>
            3. 確認 iOS 版本為 17.0 或以上<br>
            4. 如問題持續，請聯繫我們</p>
        </div>

        <div class="faq-item">
            <h3>系統需求</h3>
            <p><strong>iOS 版本：</strong>需要 iOS 17.0 或以上<br>
            <strong>裝置：</strong>支援 iPhone<br>
            <strong>儲存空間：</strong>約 50MB</p>
        </div>

        <h2>💡 使用建議</h2>
        <ul>
            <li>定期記錄訓練以追蹤進度</li>
            <li>使用組間休息計時器保持訓練節奏</li>
            <li>查看訓練容量趨勢了解訓練強度</li>
            <li>記錄個人紀錄（PR）來追蹤突破</li>
        </ul>

        <h2>📱 關於 WorkitOut</h2>
        <p>WorkitOut 是一款專為健身愛好者設計的訓練記錄 App，幫助您科學地追蹤訓練進度，突破個人極限。</p>

        <h2>📄 相關連結</h2>
        <ul>
            <li><a href="privacy.html">隱私權政策</a></li>
        </ul>

        <hr style="margin: 40px 0; border: none; border-top: 1px solid #ddd;">

        <p style="text-align: center; color: #888; font-size: 0.9em;">
            © 2025 WorkitOut. All rights reserved.
        </p>
    </div>
</body>
</html>
```

5. 點擊「Commit changes」
6. 再次點擊「Commit changes」確認

---

## 📋 步驟 3: 啟用 GitHub Pages

### 1️⃣ 進入 Repository 設定
1. 在你的 Repository 頁面
2. 點擊頂部的「Settings」（齒輪圖示）

### 2️⃣ 找到 Pages 設定
1. 在左側選單中，向下捲動找到「Pages」
2. 點擊「Pages」

### 3️⃣ 設定 Source
在「Build and deployment」區塊：

1. **Source** 選擇：`Deploy from a branch`
2. **Branch** 選擇：
   - Branch: `main`（或 `master`）
   - Folder: `/ (root)`
3. 點擊「Save」

### 4️⃣ 等待部署
- GitHub 會開始建置你的網站
- 通常需要 1-3 分鐘
- 頁面會顯示類似：
  ```
  Your site is live at https://yourusername.github.io/workitout-privacy/
  ```

---

## 📋 步驟 4: 取得網址

### 你的網址格式：
```
隱私權政策：
https://yourusername.github.io/workitout-privacy/privacy.html

支援頁面：
https://yourusername.github.io/workitout-privacy/support.html
```

**重要：** 將 `yourusername` 替換成你的 GitHub 使用者名稱！

---

## 📋 步驟 5: 填入 App Store Connect

### 1️⃣ 隱私權政策 URL

**位置：**
```
App Store Connect → WorkitOut → App 資訊
```

**填入：**
```
https://yourusername.github.io/workitout-privacy/privacy.html
```

### 2️⃣ 支援 URL

**位置：**
```
App Store Connect → WorkitOut → App 資訊
```

**填入：**
```
https://yourusername.github.io/workitout-privacy/support.html
```

### 3️⃣ 行銷 URL（選填）

如果需要，也可以填入：
```
https://yourusername.github.io/workitout-privacy/
```

---

## ✅ 驗證步驟

### 1️⃣ 檢查網頁是否正常顯示
1. 在瀏覽器開啟你的網址
2. 確認內容正確顯示
3. 確認樣式正常（有顏色和排版）

### 2️⃣ 檢查連結
- 點擊支援頁面中的「隱私權政策」連結
- 確認可以正常跳轉

### 3️⃣ 測試在手機上的顯示
- 用手機瀏覽器開啟
- 確認響應式設計正常

---

## 🔧 如果遇到問題

### 問題 1: 404 Not Found
**解決方法：**
1. 確認 GitHub Pages 已啟用
2. 等待 3-5 分鐘讓 GitHub 部署完成
3. 確認 URL 拼寫正確（注意大小寫）

### 問題 2: 網址不正確
**正確格式：**
```
https://[你的用戶名].github.io/[repo名稱]/[檔案名].html
```

**範例：**
```
https://mikelinworkitout.github.io/workitout-privacy/privacy.html
```

### 問題 3: 樣式沒有顯示
**解決方法：**
1. 確認 HTML 檔案完整貼上
2. 清除瀏覽器快取
3. 使用無痕模式測試

---

## 💡 進階：自訂域名（選填）

如果你有自己的域名（例如 workitout.app）：

1. **在 GitHub Pages 設定中**
   - 找到「Custom domain」欄位
   - 輸入你的域名：`privacy.workitout.app`
   - 儲存

2. **在你的域名 DNS 設定中**
   - 添加 CNAME 記錄
   - 指向：`yourusername.github.io`

---

## 📝 更新內容

以後如果需要更新內容：

1. 前往 GitHub Repository
2. 點擊要編輯的檔案（如 `privacy.html`）
3. 點擊右上角的「✏️ 編輯」圖示
4. 修改內容
5. 點擊「Commit changes」
6. 等待 1-2 分鐘，網頁會自動更新

---

## ✅ 完成！

完成以上步驟後，你就有了：
- ✅ 專業的隱私權政策頁面
- ✅ 完整的支援頁面
- ✅ 符合 App Store 要求的 URL
- ✅ 完全免費的解決方案

---

## 📞 需要幫助？

如果在任何步驟遇到問題：
1. 截圖給我看
2. 告訴我你的 GitHub 使用者名稱
3. 我會幫你檢查設定

---

**現在就開始吧！** 🚀

