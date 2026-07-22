# 健身記錄 App - 專案文檔

> 一個專業的健身訓練記錄 iOS App，支援體重追蹤、訓練記錄、容量分析等功能

## 📚 文檔目錄

### 核心文檔

1. **[技術選型 (TECH_STACK.md)](./TECH_STACK.md)**
   - 後端：Golang + Gin + GORM + PostgreSQL
   - 前端：Swift + SwiftUI + Swift Charts
   - 身份驗證：JWT + Apple/Google OAuth

2. **[資料庫設計 (DATABASE_SCHEMA.md)](./DATABASE_SCHEMA.md)**
   - 完整的資料表結構
   - 容量計算邏輯 ⭐
   - 索引策略
   - 資料庫觸發器

3. **[功能地圖 (FEATURE_MAP.md)](./FEATURE_MAP.md)**
   - iOS App 完整功能規劃
   - 5 個主要分頁設計
   - 容量分析功能 ⭐
   - 後台管理系統規劃

4. **[開發階段規劃 (DEVELOPMENT_PLAN.md)](./DEVELOPMENT_PLAN.md)**
   - 6 個開發階段詳細規劃
   - 每日工作清單
   - 時間估算（9-13 週）
   - 開發注意事項

5. **[API 端點文件 (API_ENDPOINTS.md)](./API_ENDPOINTS.md)**
   - 完整的 RESTful API 定義
   - Request/Response 範例
   - 認證方式說明
   - 錯誤處理

---

## 🎯 專案目標

建立一個功能完整的健身記錄 iOS App，滿足以下需求：

### 核心功能
1. ✅ **體重記錄**：手動輸入並追蹤體重變化
2. ✅ **訓練記錄**：記錄各種健身動作的重量、次數、組數
3. ✅ **容量追蹤**：計算並追蹤訓練容量（重量 × 次數 × 組數）⭐
4. ✅ **進階數據**：1RM 計算、百分比計算、PR 追蹤
5. ✅ **數據視覺化**：多種圖表展示訓練趨勢

### 技術需求
- ✅ 可上架 App Store（或使用 TestFlight 自行安裝）
- ✅ 支援 Apple Sign In & Google Sign In
- ✅ 雲端資料同步（非僅存手機）
- ✅ 預設動作庫 + 自定義動作
- ✅ 設定檔可控制
- ✅ 後台管理系統（預留）

---

## 🏗️ 專案架構

```
workout-record/
├── ios/                    # iOS App (Swift + SwiftUI)
├── backend/                # 後端 API (Golang + Gin)
├── docs/                   # 專案文檔
│   ├── README.md          # 文檔索引（本檔案）
│   ├── TECH_STACK.md      # 技術選型
│   ├── DATABASE_SCHEMA.md # 資料庫設計
│   ├── FEATURE_MAP.md     # 功能地圖
│   ├── DEVELOPMENT_PLAN.md# 開發規劃
│   └── API_ENDPOINTS.md   # API 文件
└── README.md              # 專案說明
```

---

## 📱 iOS App 功能架構

### Tab Bar (5 個分頁)

| Tab | 功能 | 說明 |
|-----|------|------|
| 🏠 首頁 | Dashboard | 今日概覽、快速操作、統計卡片 |
| 💪 訓練 | Workout | 訓練記錄、動作選擇、組數記錄、計時器 |
| 📊 數據 | Stats | 體重趨勢、訓練統計、**容量分析** ⭐ |
| 📅 歷史 | History | 日曆檢視、列表檢視、訓練詳情 |
| ⚙️ 設定 | Settings | 個人資料、動作庫、模板、應用設定 |

---

## ⭐ 核心功能：訓練容量追蹤

### 什麼是訓練容量？
```
訓練容量 = 重量 × 次數 × 組數
```

例如：臥推 100kg × 10 次 × 4 組 = 4,000 kg 容量

### 容量追蹤功能
- ✅ 即時顯示單組容量
- ✅ 訓練進行中顯示總容量
- ✅ 訓練容量趨勢圖表
- ✅ 肌群容量分布
- ✅ 週期容量對比（本週 vs 上週）
- ✅ 單一動作容量追蹤
- ✅ 容量 vs 體重關聯分析

### 為什麼重要？
訓練容量是評估訓練量最客觀的指標，可以：
- 追蹤訓練進步
- 避免過度訓練
- 平衡各肌群訓練
- 規劃訓練週期

---

## 🚀 開發流程

### 開發策略：前端優先
1. **階段 1**：完成 iOS UI/UX（使用假資料）
2. **階段 2**：本地資料持久化（CoreData/SwiftData）
3. **階段 3**：開發後端 API（Golang + PostgreSQL）
4. **階段 4**：前後端串接與雲端同步
5. **階段 5**：實作身份驗證（Apple/Google Sign In）
6. **階段 6**：測試、部署與 App Store 上架

### 預估時間
- **總計**：9-13 週（約 2-3 個月）
- **可用 MVP**：4-5 週後（完成階段 1-2）

---

## 🗄️ 資料庫核心設計

### 主要資料表
- `users` - 用戶資料
- `body_weights` - 體重記錄
- `exercises` - 動作庫（預設 + 自定義）
- `workouts` - 訓練記錄
- `workout_exercises` - 訓練動作
- `workout_sets` - 訓練組數（含容量）⭐
- `workout_templates` - 訓練模板
- `personal_records` - 個人記錄

### 容量計算邏輯
- **自動計算**：使用 Database Trigger 自動計算容量
- **三層統計**：單組 → 動作 → 訓練
- **即時更新**：任何變更自動更新上層統計

詳見 [DATABASE_SCHEMA.md](./DATABASE_SCHEMA.md)

---

## 🔌 API 設計

### RESTful API 架構
- **Base URL**: `/api/v1`
- **認證**: Bearer Token (JWT)
- **格式**: JSON

### 主要 API 群組
- `/auth/*` - 身份驗證
- `/users/*` - 用戶管理
- `/body-weights/*` - 體重記錄
- `/exercises/*` - 動作庫
- `/workouts/*` - 訓練記錄
- `/workout-templates/*` - 訓練模板
- `/personal-records/*` - 個人記錄
- `/stats/*` - 統計分析 ⭐
- `/admin/*` - 後台管理

詳見 [API_ENDPOINTS.md](./API_ENDPOINTS.md)

---

## 📊 數據分析功能

### 圖表類型
1. **折線圖**：體重趨勢、容量趨勢、1RM 進步
2. **柱狀圖**：訓練頻率、單次訓練容量
3. **圓餅圖**：肌群分布、訓練時段分布
4. **長條圖**：各肌群容量排行
5. **雙軸圖**：容量 vs 體重關聯

### 時間範圍
- 本週 / 本月 / 本季 / 本年
- 自訂範圍
- 週期對比（本週 vs 上週）

---

## 🎨 UI/UX 設計原則

### 設計理念
- **簡潔直觀**：操作流程簡單，易於上手
- **即時反饋**：所有操作立即顯示結果
- **數據可視**：重要數據一目了然
- **離線可用**：無網路也能正常記錄

### 色彩系統
- 支援淺色/深色模式
- 跟隨系統設定
- 重要數據突出顯示

### 動畫效果
- 頁面轉場流暢
- 數據變化有動畫
- 按鈕有回饋效果

---

## 🔐 安全性設計

### 身份驗證
- JWT Token 機制
- Refresh Token 自動更新
- Token 儲存於 Keychain

### 資料安全
- HTTPS 加密傳輸
- 敏感資料加密儲存
- API Key 環境變數管理

### 隱私保護
- 遵循 GDPR / Apple 隱私政策
- 最小化資料收集
- 用戶可刪除所有資料

---

## 📝 開發規範

### Git 工作流程
- `main` - 穩定版本
- `develop` - 開發主線
- `feature/*` - 功能分支
- `hotfix/*` - 緊急修復

### Commit Message 格式
```
<type>(<scope>): <subject>

<body>
```

Type:
- `feat`: 新功能
- `fix`: Bug 修復
- `docs`: 文件更新
- `style`: 格式調整
- `refactor`: 重構
- `test`: 測試相關
- `chore`: 雜項

### 程式碼風格
- **Swift**: 遵循 [Swift Style Guide](https://google.github.io/swift/)
- **Go**: 使用 `gofmt`、`golint`

---

## 📦 部署計畫

### 後端部署
- **平台選擇**：Railway / Render / AWS / GCP
- **容器化**：Docker
- **資料庫**：Managed PostgreSQL
- **監控**：日誌系統、錯誤追蹤

### iOS 部署
- **開發測試**：Xcode Simulator
- **內部測試**：TestFlight (Internal)
- **外部測試**：TestFlight (External)
- **正式上架**：App Store

---

## ✅ 開發檢查清單

### 階段 0: 專案初始化
- [ ] iOS 專案建立
- [ ] Go 專案建立
- [ ] Git 初始化
- [ ] 文檔完成 ✓

### 階段 1: iOS UI/UX (3-4 週)
- [ ] TabView 架構
- [ ] 首頁 & 體重記錄
- [ ] 訓練記錄功能
- [ ] 數據分析圖表
- [ ] 歷史記錄 & 設定

### 階段 2: 本地持久化 (1 週)
- [ ] 資料模型定義
- [ ] CoreData/SwiftData 整合
- [ ] 容量計算邏輯

### 階段 3: 後端開發 (2-3 週)
- [ ] 資料庫設計
- [ ] 基礎 CRUD API
- [ ] 訓練記錄 API
- [ ] 統計分析 API

### 階段 4: 前後端串接 (1-2 週)
- [ ] 網路層實作
- [ ] 功能串接
- [ ] 資料同步策略

### 階段 5: 身份驗證 (1 週)
- [ ] 後端 JWT 實作
- [ ] Apple Sign In
- [ ] Google Sign In

### 階段 6: 測試與上架 (1-2 週)
- [ ] 測試
- [ ] 上架準備
- [ ] 部署與發布

---

## 📞 聯絡資訊

- **專案名稱**：健身記錄 App (Workout Record)
- **開發時間**：2025-10-20 開始
- **預計完成**：2025-12 月底（2-3 個月）

---

## 📄 授權

本專案為個人使用專案

---

最後更新: 2025-10-20

