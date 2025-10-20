# 健身記錄 App (Workout Record)

> 一個專業的 iOS 健身訓練記錄 App，支援體重追蹤、訓練記錄、容量分析與數據視覺化

## 📱 專案簡介

這是一個全功能的健身記錄應用程式，設計目的是幫助使用者系統化地記錄和追蹤健身訓練數據，包括：
- 體重記錄與趨勢追蹤
- 訓練動作記錄（重量、次數、組數）
- **訓練容量分析**（重量 × 次數 × 組數）⭐
- 個人記錄追蹤與 1RM 計算
- 多維度數據視覺化圖表
- 訓練模板與自定義動作

## 🎯 核心功能

### 1. 體重管理
- 手動記錄體重
- 體重趨勢圖表
- 目標體重設定
- 體重變化統計

### 2. 訓練記錄
- 豐富的預設動作庫（器材/自由重量/徒手）
- 自定義動作
- 詳細的組數記錄（重量、次數、RPE）
- 組間計時器
- 訓練模板快速開始

### 3. 容量分析 ⭐
- 即時顯示單組容量
- 訓練總容量追蹤
- 容量趨勢圖表
- 肌群容量分布
- 週期容量對比
- 動作容量進度

### 4. 進階數據
- 1RM 計算（多種公式）
- 百分比計算（80%/85%/90% 等）
- 個人記錄（PR）追蹤
- 訓練頻率統計
- 訓練時長分析

### 5. 數據視覺化
- 體重趨勢折線圖
- 訓練容量趨勢圖
- 肌群分布圓餅圖
- 訓練頻率柱狀圖
- 多種時間範圍篩選

## 🛠️ 技術架構

### 前端 (iOS)
- **語言**: Swift
- **框架**: SwiftUI
- **圖表**: Swift Charts (iOS 16+)
- **資料**: CoreData / SwiftData
- **網路**: URLSession / Alamofire

### 後端 (API)
- **語言**: Golang
- **框架**: Gin (Web Framework)
- **ORM**: GORM
- **資料庫**: PostgreSQL
- **認證**: JWT + OAuth2.0

### 身份驗證
- Apple Sign In
- Google Sign In
- JWT Token 管理

### 部署
- **後端**: Docker + 雲端服務
- **資料庫**: Managed PostgreSQL
- **iOS**: TestFlight / App Store

## 📁 專案結構

```
workout-record/
├── ios/                    # iOS App 原始碼
│   ├── Models/            # 資料模型
│   ├── Views/             # SwiftUI 視圖
│   ├── ViewModels/        # 視圖模型
│   ├── Services/          # 服務層
│   └── Utils/             # 工具函數
│
├── backend/               # 後端 API 原始碼
│   ├── cmd/api/          # 主程式進入點
│   ├── internal/         # 內部套件
│   │   ├── models/       # 資料模型
│   │   ├── handlers/     # HTTP Handlers
│   │   ├── services/     # 業務邏輯
│   │   ├── repository/   # 資料層
│   │   └── middleware/   # 中介層
│   ├── api/              # API 定義
│   ├── migrations/       # 資料庫遷移
│   └── docs/             # API 文件
│
├── docs/                  # 專案文檔
│   ├── README.md         # 文檔索引
│   ├── TECH_STACK.md     # 技術選型
│   ├── DATABASE_SCHEMA.md# 資料庫設計
│   ├── FEATURE_MAP.md    # 功能地圖
│   ├── DEVELOPMENT_PLAN.md# 開發規劃
│   └── API_ENDPOINTS.md  # API 文件
│
└── README.md             # 本檔案
```

## 📚 文檔

完整的專案文檔請參閱 [`docs/`](./docs/) 目錄：

- **[技術選型](./docs/TECH_STACK.md)** - 技術棧詳細說明
- **[資料庫設計](./docs/DATABASE_SCHEMA.md)** - 完整的 Schema 與容量計算邏輯
- **[功能地圖](./docs/FEATURE_MAP.md)** - 所有功能的詳細規劃
- **[開發計畫](./docs/DEVELOPMENT_PLAN.md)** - 6 階段開發流程與時程
- **[API 文件](./docs/API_ENDPOINTS.md)** - RESTful API 完整定義

## 🚀 快速開始

### 環境需求

**iOS 開發:**
- macOS
- Xcode 15+
- iOS 16.0+ (Deployment Target)

**後端開發:**
- Go 1.21+
- PostgreSQL 14+
- Docker (選用)

### 安裝步驟

#### 1. Clone 專案
```bash
git clone https://github.com/yourusername/workout-record.git
cd workout-record
```

#### 2. iOS App 設定
```bash
cd ios
# 使用 Xcode 開啟專案
open WorkoutRecord.xcodeproj
```

#### 3. 後端 API 設定
```bash
cd backend
# 安裝依賴
go mod download

# 設定環境變數
cp .env.example .env
# 編輯 .env 設定資料庫連線等

# 執行資料庫遷移
go run cmd/migrate/main.go

# 啟動服務
go run cmd/api/main.go
```

#### 4. PostgreSQL 設定
```bash
# 使用 Docker
docker-compose up -d

# 或手動安裝 PostgreSQL 並建立資料庫
createdb workout_record
```

## 📖 開發指南

### 開發流程

本專案採用「前端優先」的開發策略：

1. **階段 1 (3-4週)**: 完成 iOS UI/UX（使用假資料）
2. **階段 2 (1週)**: 本地資料持久化
3. **階段 3 (2-3週)**: 後端 API 開發
4. **階段 4 (1-2週)**: 前後端串接
5. **階段 5 (1週)**: 身份驗證
6. **階段 6 (1-2週)**: 測試與上架

詳細規劃請參閱 [開發計畫](./docs/DEVELOPMENT_PLAN.md)

### Git 工作流程

```bash
# 建立功能分支
git checkout -b feature/功能名稱

# 開發並 commit
git add .
git commit -m "feat(scope): 新功能描述"

# Push 到遠端
git push origin feature/功能名稱

# 發 PR 合併到 develop
```

### Commit Message 格式
```
<type>(<scope>): <subject>

feat: 新功能
fix: Bug 修復
docs: 文件更新
style: 格式調整
refactor: 重構
test: 測試相關
chore: 雜項
```

## 🧪 測試

### iOS 測試
```bash
# 單元測試
xcodebuild test -scheme WorkoutRecord -destination 'platform=iOS Simulator,name=iPhone 15'

# UI 測試
xcodebuild test -scheme WorkoutRecordUITests -destination 'platform=iOS Simulator,name=iPhone 15'
```

### 後端測試
```bash
# 執行所有測試
go test ./...

# 測試覆蓋率
go test -cover ./...
```

## 🎨 UI/UX 預覽

（開發完成後補上截圖）

## 📊 專案進度

- [x] 專案規劃與文檔
- [ ] iOS App UI/UX 開發
- [ ] 本地資料持久化
- [ ] 後端 API 開發
- [ ] 前後端串接
- [ ] 身份驗證整合
- [ ] 測試與部署
- [ ] App Store 上架

詳細進度追蹤請參閱 [Issues](../../issues) 和 [Projects](../../projects)

## 🤝 貢獻

本專案目前為個人開發專案，暫不接受外部貢獻。

## 📝 開發日誌

- **2025-10-20**: 專案啟動，完成規劃與文檔
- 待續...

## 📄 授權

本專案為個人使用專案

## 📞 聯絡

如有問題或建議，請建立 [Issue](../../issues)

---

**開發時間**: 2025-10-20 開始  
**預計完成**: 2025-12 月底（2-3 個月）

Made with ❤️ for fitness enthusiasts
重訓訓練紀錄用app
