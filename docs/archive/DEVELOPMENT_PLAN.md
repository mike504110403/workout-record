# 開發階段規劃

## 開發策略

### 核心理念
1. **前端優先**：先完成 iOS App UI/UX（使用假資料）
2. **本地持久化**：本地資料儲存（CoreData/SwiftData）
3. **後端開發**：開發 RESTful API
4. **前後端串接**：整合雲端同步
5. **登入功能**：最後實作身份驗證
6. **測試上架**：TestFlight 測試與 App Store 上架

---

## 階段 0：專案初始化 (0.5 天)

### iOS 專案
```
✓ 建立 Xcode 專案
✓ 設定 SwiftUI + iOS 16+ 
✓ 建立基本專案結構
  ├─ Models/          # 資料模型
  ├─ Views/           # UI 視圖
  ├─ ViewModels/      # 視圖模型
  ├─ Services/        # 服務層
  ├─ Utils/           # 工具函數
  └─ Resources/       # 資源檔案
✓ 建立假資料模型（Mock Data）
✓ Git 初始化與 .gitignore
```

### 後端專案（先建立架構）
```
✓ 建立 Go 專案結構
✓ 初始化 go.mod
✓ 安裝基礎依賴
  ├─ gin
  ├─ gorm
  ├─ postgresql driver
  └─ jwt-go
✓ 建立目錄結構
  ├─ cmd/api/         # 主程式進入點
  ├─ internal/        # 內部套件
  │   ├─ models/      # 資料模型
  │   ├─ handlers/    # HTTP handlers
  │   ├─ services/    # 業務邏輯
  │   ├─ repository/  # 資料層
  │   └─ middleware/  # 中介層
  ├─ api/             # API 定義
  ├─ migrations/      # 資料庫遷移
  └─ docs/            # API 文件
✓ Git 初始化與 .gitignore
```

---

## 階段 1：iOS App UI/UX 開發 (3-4 週)

### Week 1: 基礎架構與首頁 (5 天)

#### Day 1-2: TabView 架構與導航
**工作項目：**
- [ ] 建立主 TabView（5個 Tab）
- [ ] 建立各 Tab 的空白頁面架構
- [ ] 設定導航與路由
- [ ] 建立基礎 Design System
  - [ ] Color Scheme
  - [ ] Typography
  - [ ] 共用組件（Button, Card, TextField 等）

**產出：**
- TabView 主架構
- 基礎 UI 組件庫

#### Day 3-4: 首頁 (Dashboard)
**工作項目：**
- [ ] 今日概覽卡片設計
  - [ ] 訓練狀態卡片
  - [ ] 體重趨勢小圖
  - [ ] 本週統計（次數、容量）
- [ ] 快速操作按鈕
  - [ ] 記錄體重按鈕
  - [ ] 開始訓練按鈕
  - [ ] 查看進度按鈕
- [ ] 最近訓練列表組件
- [ ] 使用假資料填充

**產出：**
- 完整的首頁 UI
- 假資料模型

#### Day 5: 體重記錄功能
**工作項目：**
- [ ] 體重輸入 Sheet 設計
  - [ ] 日期時間選擇器
  - [ ] 體重輸入欄位
  - [ ] 備註欄位
- [ ] 體重列表顯示
- [ ] 簡單的體重趨勢圖（Swift Charts）
- [ ] 編輯/刪除功能
- [ ] 使用假資料測試

**產出：**
- 體重記錄完整功能
- 基礎圖表組件

---

### Week 2: 訓練記錄核心功能 (5 天)

#### Day 1-2: 動作選擇器
**工作項目：**
- [ ] 建立 Exercise Model
- [ ] 準備預設動作假資料（50-100個）
  - [ ] 胸部動作（10-15個）
  - [ ] 背部動作（10-15個）
  - [ ] 腿部動作（10-15個）
  - [ ] 肩部動作（8-10個）
  - [ ] 手臂動作（8-10個）
  - [ ] 核心動作（8-10個）
- [ ] 動作分類列表 UI
- [ ] 動作選擇頁面
- [ ] 搜尋功能實作
- [ ] 常用動作標記功能

**產出：**
- 動作選擇器完整 UI
- 預設動作資料集

#### Day 3-5: 訓練記錄主功能
**工作項目：**
- [ ] 開始訓練頁面設計
- [ ] 添加動作到訓練流程
- [ ] 組數記錄介面
  - [ ] 重量輸入
  - [ ] 次數輸入
  - [ ] 即時顯示單組容量 (weight × reps) ⭐
  - [ ] 顯示上次訓練數據（假資料）
  - [ ] 暖身組標記
  - [ ] RPE 輸入（可選）
- [ ] 組間計時器功能
  - [ ] 倒數計時
  - [ ] 通知提醒
  - [ ] 自訂時間
- [ ] 訓練進行中頁面
  - [ ] 顯示當前訓練總容量 ⭐
  - [ ] 顯示已完成組數
  - [ ] 訓練時長計時
  - [ ] 動作列表
- [ ] 完成訓練流程
  - [ ] 儲存訓練
  - [ ] 放棄訓練確認

**產出：**
- 完整訓練記錄功能
- 容量計算邏輯實作 ⭐

---

### Week 3: 數據分析與圖表 (5 天)

#### Day 1-2: 基礎統計圖表
**工作項目：**
- [ ] 體重趨勢圖（Swift Charts）
  - [ ] 折線圖實作
  - [ ] 時間範圍選擇器
  - [ ] 數據點標記
  - [ ] 目標體重線
- [ ] 訓練頻率圖
  - [ ] 柱狀圖實作
  - [ ] 週/月視圖切換
- [ ] 訓練時長統計圖
  - [ ] 平均時長顯示
  - [ ] 趨勢線

**產出：**
- 基礎圖表組件庫
- 體重與訓練統計頁面

#### Day 3-4: 容量分析圖表 ⭐
**工作項目：**
- [ ] 訓練容量趨勢圖
  - [ ] 總容量折線圖
  - [ ] 單次訓練柱狀圖
  - [ ] 移動平均線
  - [ ] 時間範圍選擇（週/月/季/年）
- [ ] 肌群容量分布圖
  - [ ] 圓餅圖實作
  - [ ] 長條圖實作
  - [ ] 百分比顯示
- [ ] 週期容量對比
  - [ ] 本週 vs 上週對比
  - [ ] 百分比變化顯示
  - [ ] 趨勢指示（↑↓）
- [ ] 統計資訊卡片
  - [ ] 本週/本月總容量
  - [ ] 平均容量
  - [ ] 最高容量

**產出：**
- 完整容量分析頁面 ⭐
- 進階圖表組件

#### Day 5: 動作詳細分析
**工作項目：**
- [ ] 單一動作詳情頁
- [ ] 動作重量進度圖
- [ ] 動作容量趨勢圖 ⭐
- [ ] 1RM 計算實作
  - [ ] Epley 公式
  - [ ] Brzycki 公式
  - [ ] 公式選擇器
- [ ] 百分比計算（80%/85%/90% 等）
- [ ] PR 記錄顯示
- [ ] 最近訓練記錄列表

**產出：**
- 動作詳細分析頁面
- 1RM 計算工具

---

### Week 4: 歷史記錄與設定 (5 天)

#### Day 1-2: 歷史記錄
**工作項目：**
- [ ] 日曆檢視實作
  - [ ] 月曆 UI
  - [ ] 訓練日標記
  - [ ] 點擊查看詳情
- [ ] 列表檢視實作
  - [ ] 訓練卡片設計
  - [ ] 排序功能
  - [ ] 無限滾動
- [ ] 訓練詳情頁
  - [ ] 顯示總容量 ⭐
  - [ ] 顯示所有動作與組數
  - [ ] 統計資訊
- [ ] 編輯功能
  - [ ] 編輯組數
  - [ ] 新增/刪除組數
  - [ ] 編輯備註
- [ ] 刪除功能
- [ ] 搜尋與篩選

**產出：**
- 完整歷史記錄功能
- 日曆與列表檢視

#### Day 3-4: 設定頁面
**工作項目：**
- [ ] 個人資料設定
  - [ ] 個人資訊表單
  - [ ] 目標設定
- [ ] 動作庫管理
  - [ ] 動作列表
  - [ ] 自定義動作表單
  - [ ] 編輯動作
  - [ ] 隱藏/排序動作
  - [ ] 常用動作管理
- [ ] 訓練模板管理
  - [ ] 模板列表
  - [ ] 建立模板表單
  - [ ] 編輯模板
  - [ ] 刪除模板
  - [ ] 使用模板開始訓練
- [ ] 應用設定
  - [ ] 單位切換（kg/lb）
  - [ ] 主題設定（淺色/深色）
  - [ ] 1RM 公式選擇
  - [ ] 組間休息預設時間
  - [ ] 通知設定

**產出：**
- 完整設定功能
- 動作庫與模板管理

#### Day 5: UI/UX 優化
**工作項目：**
- [ ] 整體 UI 美化
  - [ ] 一致性檢查
  - [ ] 色彩調整
  - [ ] 間距優化
- [ ] 動畫效果
  - [ ] 頁面轉場
  - [ ] 按鈕動畫
  - [ ] 載入動畫
- [ ] 錯誤處理 UI
  - [ ] 錯誤提示
  - [ ] 驗證提示
- [ ] Loading 狀態
- [ ] 空狀態設計
  - [ ] 無資料提示
  - [ ] 引導文案
- [ ] 細節打磨

**產出：**
- 優化後的完整 App UI

---

## 階段 2：資料層與本地持久化 (1 週)

### Day 1-2: 資料模型定義
**工作項目：**
- [ ] 定義完整的 Data Models
  - [ ] User Model
  - [ ] BodyWeight Model
  - [ ] Exercise Model
  - [ ] ExerciseCategory Model
  - [ ] Workout Model
  - [ ] WorkoutExercise Model
  - [ ] WorkoutSet Model (含 volume) ⭐
  - [ ] WorkoutTemplate Model
  - [ ] PersonalRecord Model
- [ ] 實作容量計算邏輯 ⭐
  - [ ] 單組容量計算
  - [ ] 動作總容量計算
  - [ ] 訓練總容量計算
- [ ] 實作 1RM 計算邏輯
- [ ] 資料驗證邏輯

**產出：**
- 完整的資料模型定義
- 計算邏輯實作

### Day 3-5: CoreData / SwiftData 整合
**工作項目：**
- [ ] 選擇資料持久化方案
  - [ ] CoreData (iOS 16+)
  - [ ] SwiftData (iOS 17+)
- [ ] 設定 CoreData / SwiftData
- [ ] 建立所有 Entity
- [ ] 實作 Repository 層
  - [ ] BodyWeightRepository
  - [ ] ExerciseRepository
  - [ ] WorkoutRepository
  - [ ] TemplateRepository
  - [ ] PersonalRecordRepository
- [ ] 實作 CRUD 操作
- [ ] 容量自動計算與儲存 ⭐
- [ ] 資料遷移策略
- [ ] 將假資料替換為本地資料
- [ ] 測試資料持久化

**產出：**
- 完整的本地資料層
- App 可離線完整使用

---

## 階段 3：後端開發 (2-3 週)

### Week 1: 資料庫與基礎 API (5 天)

#### Day 1-2: 資料庫設計
**工作項目：**
- [ ] PostgreSQL 安裝與設定
  - [ ] 本地開發環境
  - [ ] Docker 配置（可選）
- [ ] 定義所有 GORM Models
  - [ ] User
  - [ ] BodyWeight
  - [ ] Exercise
  - [ ] ExerciseCategory
  - [ ] Workout
  - [ ] WorkoutExercise
  - [ ] WorkoutSet
  - [ ] WorkoutTemplate
  - [ ] WorkoutTemplateExercise
  - [ ] PersonalRecord
  - [ ] UserExerciseSetting
- [ ] 實作 Auto Migration
- [ ] 建立測試資料 Seeder
  - [ ] 動作分類
  - [ ] 預設動作（50-100個）
- [ ] 實作容量計算 Trigger/Hook ⭐

**產出：**
- 完整資料庫 Schema
- Migration 腳本
- Seed 資料

#### Day 3-5: 基礎 CRUD API
**工作項目：**
- [ ] Gin 專案基礎設定
  - [ ] Router 配置
  - [ ] CORS 設定
  - [ ] 錯誤處理 Middleware
  - [ ] Logger Middleware
- [ ] 體重記錄 API
  - [ ] `GET /api/v1/body-weights`
  - [ ] `POST /api/v1/body-weights`
  - [ ] `PUT /api/v1/body-weights/:id`
  - [ ] `DELETE /api/v1/body-weights/:id`
- [ ] 動作庫 API
  - [ ] `GET /api/v1/exercises`（支援分類、搜尋）
  - [ ] `GET /api/v1/exercises/:id`
  - [ ] `POST /api/v1/exercises`（自定義動作）
  - [ ] `PUT /api/v1/exercises/:id`
  - [ ] `DELETE /api/v1/exercises/:id`
  - [ ] `GET /api/v1/exercise-categories`
- [ ] 用戶動作設定 API
  - [ ] `GET /api/v1/user-exercise-settings`
  - [ ] `PUT /api/v1/user-exercise-settings/:exercise_id`
- [ ] API 測試（Postman/Insomnia）

**產出：**
- 基礎 CRUD API
- API 測試集合

---

### Week 2: 訓練記錄 API (5 天)

#### Day 1-3: 訓練 API
**工作項目：**
- [ ] 訓練記錄 API
  - [ ] `GET /api/v1/workouts`（分頁、篩選）
  - [ ] `GET /api/v1/workouts/:id`
  - [ ] `POST /api/v1/workouts`
  - [ ] `PUT /api/v1/workouts/:id`
  - [ ] `DELETE /api/v1/workouts/:id`
- [ ] 訓練動作 API
  - [ ] `POST /api/v1/workout-exercises`
  - [ ] `PUT /api/v1/workout-exercises/:id`
  - [ ] `DELETE /api/v1/workout-exercises/:id`
- [ ] 組數記錄 API
  - [ ] `POST /api/v1/workout-sets`
  - [ ] `PUT /api/v1/workout-sets/:id`
  - [ ] `DELETE /api/v1/workout-sets/:id`
- [ ] 容量自動計算邏輯 ⭐
  - [ ] 單組容量計算
  - [ ] 動作總容量計算
  - [ ] 訓練總容量計算
  - [ ] 自動更新上層統計
- [ ] 交易處理（Transaction）
- [ ] API 測試

**產出：**
- 完整訓練記錄 API
- 容量自動計算機制 ⭐

#### Day 4-5: 統計與分析 API
**工作項目：**
- [ ] Dashboard API
  - [ ] `GET /api/v1/stats/dashboard`
- [ ] 體重統計 API
  - [ ] `GET /api/v1/stats/body-weight-trend`
- [ ] 訓練統計 API
  - [ ] `GET /api/v1/stats/workout-frequency`
  - [ ] `GET /api/v1/stats/workout-duration`
- [ ] 容量統計 API ⭐
  - [ ] `GET /api/v1/stats/volume-trend`
  - [ ] `GET /api/v1/stats/volume-by-exercise/:id`
  - [ ] `GET /api/v1/stats/volume-by-muscle-group`
  - [ ] `GET /api/v1/stats/volume-comparison`（週期對比）
- [ ] 個人記錄 API
  - [ ] `GET /api/v1/personal-records`
  - [ ] `GET /api/v1/personal-records/exercise/:id`
  - [ ] `GET /api/v1/personal-records/top`
- [ ] 查詢優化
- [ ] API 測試

**產出：**
- 完整統計分析 API
- 容量趨勢 API ⭐

---

### Week 3: 進階功能與優化 (5 天)

#### Day 1-2: 訓練模板 API
**工作項目：**
- [ ] 訓練模板 API
  - [ ] `GET /api/v1/workout-templates`
  - [ ] `GET /api/v1/workout-templates/:id`
  - [ ] `POST /api/v1/workout-templates`
  - [ ] `PUT /api/v1/workout-templates/:id`
  - [ ] `DELETE /api/v1/workout-templates/:id`
- [ ] 模板動作 API
  - [ ] 包含在模板 API 中（nested）
- [ ] 從模板創建訓練
- [ ] API 測試

**產出：**
- 訓練模板 API

#### Day 3-5: 後台管理 API 與優化
**工作項目：**
- [ ] Admin API (簡單版本)
  - [ ] `POST /api/v1/admin/exercises`（批量新增）
  - [ ] `PUT /api/v1/admin/exercises/:id`
  - [ ] `DELETE /api/v1/admin/exercises/:id`
  - [ ] `GET /api/v1/admin/stats/system`
- [ ] API 優化
  - [ ] 分頁實作
  - [ ] 排序實作
  - [ ] 篩選實作
  - [ ] 查詢效能優化
  - [ ] 索引優化
- [ ] 錯誤處理完善
- [ ] 資料驗證
- [ ] API 文件（Swagger/OpenAPI - 可選）
- [ ] 單元測試（重要 API）

**產出：**
- 後台管理 API
- 優化後的 API
- API 文件

---

## 階段 4：前後端串接 (1-2 週)

### Day 1-2: 網路層實作
**工作項目：**
- [ ] API Client 建立
  - [ ] Base URL 配置
  - [ ] Request 封裝
  - [ ] Response 處理
- [ ] Request/Response Models
  - [ ] DTO (Data Transfer Objects)
  - [ ] Codable 實作
- [ ] 錯誤處理
  - [ ] HTTP 錯誤處理
  - [ ] 網路錯誤處理
  - [ ] 業務錯誤處理
- [ ] Loading 狀態管理
  - [ ] Loading Indicator
  - [ ] 多重請求管理
- [ ] 環境配置
  - [ ] Development
  - [ ] Production

**產出：**
- 完整網路層
- API Service 類別

### Day 3-5: 功能串接
**工作項目：**
- [ ] 體重記錄同步
  - [ ] 拉取雲端資料
  - [ ] 上傳本地資料
  - [ ] 更新/刪除同步
- [ ] 訓練記錄同步
  - [ ] 完整訓練資料同步
  - [ ] 容量計算驗證 ⭐
- [ ] 動作庫同步
  - [ ] 預設動作下載
  - [ ] 自定義動作同步
  - [ ] 動作設定同步
- [ ] 統計資料串接
  - [ ] Dashboard 資料
  - [ ] 容量趨勢資料 ⭐
  - [ ] 圖表資料更新
- [ ] 模板同步
- [ ] 功能測試

**產出：**
- 完整雲端同步功能

### Day 6-8: 資料同步策略
**工作項目：**
- [ ] 本地優先策略
  - [ ] 本地資料為主
  - [ ] 背景同步
- [ ] 離線模式支援
  - [ ] 離線記錄
  - [ ] 待同步佇列
  - [ ] 同步狀態標記
- [ ] 資料衝突處理
  - [ ] 時間戳比較
  - [ ] 衝突解決策略（最新優先）
- [ ] 同步狀態指示
  - [ ] 同步中指示
  - [ ] 同步完成提示
  - [ ] 同步失敗處理
- [ ] 增量同步
  - [ ] 只同步變更資料
  - [ ] 時間範圍同步
- [ ] 效能優化
  - [ ] 批量操作
  - [ ] 請求合併

**產出：**
- 完善的同步機制
- 離線支援

### Day 9-10: 整合測試與修復
**工作項目：**
- [ ] 整合測試
  - [ ] 端到端測試
  - [ ] 各功能流程測試
  - [ ] 容量計算準確性測試 ⭐
- [ ] Bug 修復
- [ ] 效能測試
  - [ ] API 回應時間
  - [ ] App 載入速度
  - [ ] 圖表渲染效能
- [ ] 使用者體驗優化

**產出：**
- 穩定的完整應用

---

## 階段 5：身份驗證 (1 週)

### Day 1-2: 後端身份驗證
**工作項目：**
- [ ] JWT 實作
  - [ ] Token 生成
  - [ ] Token 驗證
  - [ ] Refresh Token 機制
- [ ] Apple Sign In 驗證
  - [ ] Apple ID Token 驗證
  - [ ] 用戶創建/綁定
- [ ] Google Sign In 驗證
  - [ ] Google ID Token 驗證
  - [ ] 用戶創建/綁定
- [ ] Auth Middleware
  - [ ] Token 解析
  - [ ] 用戶身份驗證
  - [ ] 權限檢查
- [ ] API 加上身份驗證
  - [ ] 更新所有需要驗證的 API
  - [ ] Admin API 權限控制

**產出：**
- 完整後端身份驗證系統

### Day 3-5: iOS 登入流程
**工作項目：**
- [ ] Apple Sign In 整合
  - [ ] Sign in with Apple SDK
  - [ ] Authorization Flow
  - [ ] ID Token 取得
- [ ] Google Sign In 整合
  - [ ] Google Sign In SDK
  - [ ] Authorization Flow
  - [ ] ID Token 取得
- [ ] Token 管理
  - [ ] Token 儲存（Keychain）
  - [ ] Token 刷新邏輯
  - [ ] Token 過期處理
- [ ] 登入/登出流程
  - [ ] 登入頁面 UI
  - [ ] 登入流程
  - [ ] 登出功能
  - [ ] 自動登入
- [ ] 資料遷移
  - [ ] 本地資料上傳
  - [ ] 用戶資料合併
- [ ] 帳號管理
  - [ ] 帳號綁定
  - [ ] 帳號解綁
  - [ ] 刪除帳號功能
- [ ] 測試
  - [ ] 登入流程測試
  - [ ] Token 刷新測試
  - [ ] 登出測試

**產出：**
- 完整登入系統
- 用戶身份管理

---

## 階段 6：測試與上架 (1-2 週)

### Day 1-3: 測試
**工作項目：**
- [ ] 單元測試
  - [ ] Model 測試
  - [ ] ViewModel 測試
  - [ ] 計算邏輯測試（容量、1RM）⭐
  - [ ] Repository 測試
- [ ] UI 測試
  - [ ] 主要流程測試
  - [ ] 頁面導航測試
- [ ] 整合測試
  - [ ] API 整合測試
  - [ ] 資料同步測試
- [ ] 效能測試
  - [ ] 記憶體使用
  - [ ] CPU 使用
  - [ ] 網路效能
  - [ ] 圖表渲染效能
- [ ] 容量計算準確性測試 ⭐
  - [ ] 各種組合測試
  - [ ] 邊界條件測試
- [ ] 相容性測試
  - [ ] 不同 iOS 版本
  - [ ] 不同裝置尺寸
- [ ] Bug 修復

**產出：**
- 測試報告
- 穩定版本

### Day 4-7: 上架準備
**工作項目：**
- [ ] App Icon 設計
  - [ ] 各尺寸 Icon
  - [ ] App Store Icon
- [ ] Launch Screen 設計
- [ ] App Store 素材
  - [ ] 截圖（各尺寸）
  - [ ] Preview 影片（可選）
- [ ] App Store 資訊
  - [ ] App 名稱
  - [ ] 副標題
  - [ ] 描述文案（中英文）
  - [ ] 關鍵字
  - [ ] 分類選擇
- [ ] 隱私權政策
  - [ ] 撰寫隱私權政策
  - [ ] 託管隱私權政策頁面
- [ ] 服務條款（可選）
- [ ] App Store Connect 設定
  - [ ] 建立 App ID
  - [ ] 設定 Bundle ID
  - [ ] 設定 Capabilities
  - [ ] 簽署憑證
- [ ] TestFlight Beta 測試
  - [ ] 上傳 Beta 版本
  - [ ] 內部測試
  - [ ] 外部測試（可選）
  - [ ] 收集反饋
  - [ ] Bug 修復

**產出：**
- 完整上架素材
- Beta 測試版本

### Day 8-10: 部署與上架
**工作項目：**
- [ ] 後端部署
  - [ ] 選擇雲端平台
    - Railway
    - Render
    - AWS
    - GCP
    - 自架 VPS
  - [ ] Docker 配置
  - [ ] 環境變數設定
  - [ ] PostgreSQL 設定
  - [ ] 部署流程
  - [ ] CI/CD 設定（可選）
- [ ] 資料庫部署
  - [ ] Production 資料庫
  - [ ] Migration 執行
  - [ ] Seed 資料匯入
  - [ ] 備份策略
- [ ] 監控與日誌
  - [ ] 日誌系統
  - [ ] 錯誤追蹤
  - [ ] 效能監控
- [ ] App Store 提交
  - [ ] 最終版本打包
  - [ ] 提交審核
  - [ ] 審核追蹤
- [ ] 準備審核問題回覆
- [ ] 審核通過後發布

**產出：**
- 上線的後端服務
- App Store 上架的 App

---

## 持續改進（上架後）

### 短期（1-2 個月）
- [ ] 收集用戶反饋
- [ ] Bug 修復
- [ ] 效能優化
- [ ] 補充預設動作庫

### 中期（3-6 個月）
- [ ] 後台管理系統開發
- [ ] 新增更多圖表類型
- [ ] 社交功能考量
- [ ] Apple Watch 支援（可選）

### 長期（6 個月以上）
- [ ] Android 版本（可選）
- [ ] Web 版本（可選）
- [ ] 進階訓練計畫
- [ ] AI 訓練建議（可選）

---

## 時間估算總覽

| 階段 | 時間 | 說明 |
|-----|------|------|
| 階段 0：專案初始化 | 0.5 天 | 建立專案結構 |
| 階段 1：iOS UI/UX | 3-4 週 | 前端開發（假資料） |
| 階段 2：本地持久化 | 1 週 | CoreData/SwiftData |
| 階段 3：後端開發 | 2-3 週 | Go + PostgreSQL |
| 階段 4：前後端串接 | 1-2 週 | API 整合 |
| 階段 5：身份驗證 | 1 週 | Apple/Google Sign In |
| 階段 6：測試與上架 | 1-2 週 | 測試、部署、上架 |
| **總計** | **9-13 週** | **約 2-3 個月** |

---

## 開發注意事項

### 1. 版本控制
- 定期 Commit
- 有意義的 Commit Message
- Feature Branch 開發
- 定期 Push 到遠端

### 2. 程式碼品質
- 遵循 Swift Style Guide
- 遵循 Go Best Practices
- 適當的註解
- Code Review（如有團隊）

### 3. 資料安全
- 敏感資料加密
- API Key 不要 Commit
- 使用環境變數

### 4. 效能考量
- 圖表資料分頁載入
- 圖片壓縮
- 資料庫查詢優化
- 適當的快取策略

### 5. 使用者體驗
- Loading 狀態提示
- 錯誤訊息友善
- 離線可用
- 操作流暢

---

最後更新: 2025-10-20

