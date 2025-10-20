# 🚀 快速開始指南

## ✅ 當前狀態

- ✅ 後端 API 完成（Golang + Gin + Mock 資料）
- ✅ iOS API Service 層完成
- ✅ iOS 前端 UI 完成
- ⏳ Xcode 專案設定（等待 iOS 26 安裝完成）

---

## 📱 方法 1：運行後端 API

### 啟動後端

```bash
cd backend
./start.sh

# 或使用 Makefile
make run

# 或直接運行
go run cmd/server/main.go
```

### 測試 API

**健康檢查**：
```bash
curl http://localhost:8080/health
```

**獲取體重記錄**：
```bash
curl http://localhost:8080/api/v1/body-weights
```

**獲取動作列表**：
```bash
curl http://localhost:8080/api/v1/exercises
```

**登入**：
```bash
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"provider":"apple","token":"test_token"}'
```

---

## 🍎 方法 2：運行 iOS App（Xcode 安裝完成後）

### 步驟 1: 創建 Xcode 專案

1. 開啟 **Xcode**
2. **File > New > Project**
3. 選擇 **iOS > App**
4. 填寫資訊：
   ```
   Product Name: WorkoutRecord
   Interface: SwiftUI
   Language: Swift
   Storage: None
   儲存到: /Users/mike/Documents/self/workout-record/ios/
   ```

### 步驟 2: 設定專案

1. **刪除** Xcode 自動生成的 `ContentView.swift` 和 `WorkoutRecordApp.swift`
2. 在 Finder 開啟 `/Users/mike/Documents/self/workout-record/ios/Sources/`
3. **拖曳整個 Sources 資料夾**到 Xcode 專案中
4. 勾選：
   - ✅ Copy items if needed
   - ✅ Create groups
   - ✅ Add to targets: WorkoutRecord
5. 設定 **iOS Deployment Target** 為 **16.0**

### 步驟 3: 運行 App

1. 選擇 **iPhone 15 或以上模擬器**（不要選 Mac）
2. **Cmd + R** 運行

---

## 🔗 前後端整合測試

### 1. 啟動後端

```bash
cd backend
./start.sh
```

後端運行在 `http://localhost:8080`

### 2. 運行 iOS App

在 Xcode 中運行 App，App 會自動連接到 localhost:8080

### 3. 測試流程

1. **登入** - 首次進入自動登入
2. **查看體重記錄** - 查看 Mock 資料（30 筆記錄）
3. **添加體重** - 測試創建功能
4. **查看動作列表** - 查看 5 個預設動作
5. **開始訓練** - 測試完整訓練流程
6. **查看圖表** - 查看資料視覺化

---

## 📂 專案結構

```
workout-record/
├── backend/              ← 後端 API
│   ├── cmd/server/
│   ├── internal/
│   ├── config/
│   ├── start.sh         ← 啟動腳本
│   ├── Makefile
│   └── README.md
│
├── ios/                  ← iOS App
│   ├── Sources/
│   │   ├── Views/       ← UI 頁面
│   │   ├── ViewModels/
│   │   ├── Models/
│   │   ├── Services/    ← API Services
│   │   ├── Utils/
│   │   └── Data/
│   ├── HOW_TO_RUN.md
│   └── SETUP_GUIDE.md
│
├── docs/                 ← 文檔
├── INTEGRATION_GUIDE.md
├── API_INTEGRATION_STATUS.md
└── QUICK_START.md       ← 本文檔
```

---

## 🎯 下一步

### 選項 A：完成 iOS App 設定（推薦）

等 Xcode 安裝完成後：
1. 按照上方「運行 iOS App」步驟創建專案
2. 運行 App 並測試前後端整合

### 選項 B：測試後端 API

可以現在就測試後端：
```bash
cd backend
./start.sh
```

然後用 curl 或 Postman 測試各個端點

### 選項 C：開發進階功能

- PostgreSQL 資料庫整合
- JWT 認證實作
- Apple/Google OAuth
- 部署到雲端

---

## 📝 API 端點總覽

| 方法 | 端點 | 說明 |
|------|------|------|
| GET | `/health` | 健康檢查 |
| POST | `/api/v1/auth/login` | 登入 |
| GET | `/api/v1/auth/profile` | 獲取個人資料 |
| PUT | `/api/v1/auth/profile` | 更新個人資料 |
| GET | `/api/v1/body-weights` | 獲取體重記錄 |
| POST | `/api/v1/body-weights` | 創建體重記錄 |
| DELETE | `/api/v1/body-weights/:id` | 刪除體重記錄 |
| GET | `/api/v1/exercises` | 獲取動作列表 |
| GET | `/api/v1/exercises/:id` | 獲取動作詳情 |
| POST | `/api/v1/exercises` | 創建自訂動作 |
| GET | `/api/v1/workouts` | 獲取訓練列表 |
| POST | `/api/v1/workouts` | 開始新訓練 |
| GET | `/api/v1/workouts/:id` | 獲取訓練詳情 |
| PUT | `/api/v1/workouts/:id/end` | 結束訓練 |
| POST | `/api/v1/workouts/:id/exercises` | 添加動作 |
| POST | `/api/v1/workouts/:id/exercises/:exercise_id/sets` | 添加組數 |

---

## 🐛 常見問題

### Q: 後端啟動失敗，端口被佔用

```bash
# 查找佔用端口的進程
lsof -ti:8080

# 終止進程
lsof -ti:8080 | xargs kill -9

# 或使用啟動腳本，會自動處理
./start.sh
```

### Q: iOS App 無法連接後端

1. 確認後端正在運行：`curl http://localhost:8080/health`
2. 確認 `APIConfig.swift` 中的 baseURL 設定正確
3. 確認使用 iPhone 模擬器（不是 Mac）

### Q: Xcode 編譯錯誤

1. 確認 Deployment Target 是 iOS 16.0
2. 確認所有檔案都加入了 Target
3. Clean Build Folder：Cmd + Shift + K

---

## 💡 提示

- 📚 詳細文檔請參考各個 README 檔案
- 🔗 前後端整合指南：`INTEGRATION_GUIDE.md`
- 📊 完成度報告：`API_INTEGRATION_STATUS.md`
- 🏃 iOS 運行指南：`ios/HOW_TO_RUN.md`

---

**準備好了嗎？開始吧！** 🚀

1. 先啟動後端：`cd backend && ./start.sh`
2. 等 Xcode 安裝完成後創建 iOS 專案
3. 運行 App 並測試整合！

需要幫助隨時詢問！💪

