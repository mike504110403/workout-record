# Workout Record Backend

健身記錄應用後端 API，使用 Golang + Gin + PostgreSQL（目前使用 Mock 資料）

## 🚀 快速開始

### 前置需求

- Go 1.21+
- PostgreSQL 15+（未來需要）

### 安裝依賴

```bash
go mod download
```

### 運行開發伺服器

```bash
# 方式 1: 直接運行
go run cmd/server/main.go

# 方式 2: 使用 Makefile
make run

# 方式 3: 編譯後運行
make build
./bin/server
```

伺服器將在 `http://localhost:8080` 啟動

### 健康檢查

```bash
curl http://localhost:8080/health
```

## 📁 專案結構

```
backend/
├── cmd/
│   └── server/          # 主程式入口
│       └── main.go
├── internal/
│   ├── api/             # API handlers 和路由
│   │   ├── router.go
│   │   ├── auth_handler.go
│   │   ├── body_weight_handler.go
│   │   ├── exercise_handler.go
│   │   └── workout_handler.go
│   ├── models/          # 資料庫模型（含 GORM tags）
│   │   ├── user.go
│   │   ├── body_weight.go
│   │   ├── exercise.go
│   │   └── workout.go
│   ├── dto/             # API 請求/回應結構
│   │   ├── response.go
│   │   ├── user.go
│   │   ├── body_weight.go
│   │   ├── exercise.go
│   │   └── workout.go
│   ├── database/        # 資料庫連接和 migration
│   │   └── database.go
│   └── mock/            # Mock 資料儲存（暫時替代資料庫）
│       └── store.go
├── config/              # 配置管理
│   └── config.go
├── go.mod
├── go.sum
├── Makefile
├── .env.example
├── .gitignore
└── README.md
```

## 📡 API 端點

### 認證 (Auth)

- `POST /api/v1/auth/login` - 登入
- `GET /api/v1/auth/profile` - 獲取用戶資料
- `PUT /api/v1/auth/profile` - 更新用戶資料

### 體重記錄 (Body Weight)

- `GET /api/v1/body-weights` - 獲取體重記錄列表
- `POST /api/v1/body-weights` - 創建體重記錄
- `DELETE /api/v1/body-weights/:id` - 刪除體重記錄

### 動作 (Exercise)

- `GET /api/v1/exercises` - 獲取動作列表
- `GET /api/v1/exercises/:id` - 獲取動作詳情
- `POST /api/v1/exercises` - 創建自訂動作

### 訓練 (Workout)

- `GET /api/v1/workouts` - 獲取訓練列表
- `POST /api/v1/workouts` - 開始新訓練
- `GET /api/v1/workouts/:id` - 獲取訓練詳情
- `PUT /api/v1/workouts/:id/end` - 結束訓練
- `POST /api/v1/workouts/:id/exercises` - 添加動作到訓練
- `POST /api/v1/workouts/:workout_id/exercises/:exercise_id/sets` - 添加組數

## 🔧 配置

複製 `.env.example` 為 `.env` 並修改配置：

```bash
cp .env.example .env
```

## 📝 回應格式

所有 API 回應遵循統一格式：

```json
{
  "code": 200,
  "message": "Success",
  "data": { ... }
}
```

錯誤回應：

```json
{
  "code": 400,
  "message": "Error message",
  "data": null
}
```

## 🗄️ 資料庫 Migration

目前使用 Mock 資料，未來接入 PostgreSQL 後：

```bash
# 自動 migration 會在啟動時執行
# 或手動執行：
go run cmd/migrate/main.go
```

## 📦 依賴

- [Gin](https://github.com/gin-gonic/gin) - Web 框架
- [GORM](https://gorm.io/) - ORM
- [UUID](https://github.com/google/uuid) - UUID 生成
- [CORS](https://github.com/gin-contrib/cors) - CORS 中間件

## 🚧 開發狀態

- [x] 專案結構建立
- [x] Models 定義（含 GORM tags）
- [x] DTO 分離
- [x] Mock 資料層
- [x] API Handlers 實作
- [x] 路由配置
- [ ] PostgreSQL 整合
- [ ] JWT 認證
- [ ] Apple/Google OAuth
- [ ] 部署配置（Docker）

## 📄 授權

私人專案

