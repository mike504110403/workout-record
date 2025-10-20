# 前後端整合指南

## 🎯 目前狀態

### ✅ 已完成

#### 後端 (Go + Gin)
- ✅ 專案結構建立
- ✅ Models 定義（含 GORM tags，支援 auto migration）
- ✅ DTO 層（API 請求/回應分離）
- ✅ Mock 資料儲存層
- ✅ API Handlers 實作（認證、體重、動作、訓練）
- ✅ 路由配置
- ✅ 統一回應格式（code, data, message）

#### iOS 前端 (SwiftUI)
- ✅ 完整 UI 實作（5 個 Tab）
- ✅ API Config 和端點配置
- ✅ HTTP Client 封裝
- ✅ API Service 層（Auth, BodyWeight, Exercise, Workout）
- ✅ 錯誤處理結構

### ⏳ 待完成

- [ ] iOS ViewModels 整合 API（移除 Mock 資料）
- [ ] 加入 Loading 狀態和錯誤處理 UI
- [ ] 後端連接真實 PostgreSQL
- [ ] JWT 認證實作
- [ ] Apple/Google OAuth 整合

---

## 🚀 測試前後端整合

### 步驟 1: 啟動後端

```bash
cd backend
make run

# 或
go run cmd/server/main.go
```

後端將在 `http://localhost:8080` 啟動

### 步驟 2: 測試 API 端點

#### 健康檢查
```bash
curl http://localhost:8080/health
```

預期回應：
```json
{
  "code": 200,
  "message": "Server is running",
  "data": {
    "status": "healthy"
  }
}
```

#### 登入
```bash
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "apple",
    "token": "test_token"
  }'
```

#### 獲取體重記錄
```bash
curl http://localhost:8080/api/v1/body-weights
```

#### 獲取動作列表
```bash
curl http://localhost:8080/api/v1/exercises
```

#### 開始訓練
```bash
curl -X POST http://localhost:8080/api/v1/workouts \
  -H "Content-Type: application/json" \
  -d '{
    "start_time": "2025-10-20T15:00:00Z",
    "name": "今日訓練"
  }'
```

### 步驟 3: iOS App 連接後端

1. **確保後端正在運行** (`http://localhost:8080`)

2. **在 Xcode 運行 iOS App**
   - 選擇 iPhone 模擬器
   - 按 Cmd + R 運行

3. **iOS App 將自動連接到 localhost:8080**
   - 配置在 `APIConfig.swift` 中
   - Debug 模式自動使用 localhost

---

## 📋 API 端點總覽

### 認證 (Auth)

| 方法 | 端點 | 說明 |
|------|------|------|
| POST | `/api/v1/auth/login` | 登入 |
| GET | `/api/v1/auth/profile` | 獲取個人資料 |
| PUT | `/api/v1/auth/profile` | 更新個人資料 |

### 體重記錄 (Body Weight)

| 方法 | 端點 | 說明 |
|------|------|------|
| GET | `/api/v1/body-weights` | 獲取記錄列表 |
| POST | `/api/v1/body-weights` | 創建記錄 |
| DELETE | `/api/v1/body-weights/:id` | 刪除記錄 |

### 動作 (Exercise)

| 方法 | 端點 | 說明 |
|------|------|------|
| GET | `/api/v1/exercises` | 獲取動作列表 |
| GET | `/api/v1/exercises/:id` | 獲取動作詳情 |
| POST | `/api/v1/exercises` | 創建自訂動作 |

### 訓練 (Workout)

| 方法 | 端點 | 說明 |
|------|------|------|
| GET | `/api/v1/workouts` | 獲取訓練列表 |
| POST | `/api/v1/workouts` | 開始新訓練 |
| GET | `/api/v1/workouts/:id` | 獲取訓練詳情 |
| PUT | `/api/v1/workouts/:id/end` | 結束訓練 |
| POST | `/api/v1/workouts/:id/exercises` | 添加動作到訓練 |
| POST | `/api/v1/workouts/:workout_id/exercises/:exercise_id/sets` | 添加組數 |

---

## 📝 API 回應格式

### 成功回應
```json
{
  "code": 200,
  "message": "Success",
  "data": {
    // 實際資料
  }
}
```

### 錯誤回應
```json
{
  "code": 400,
  "message": "錯誤訊息",
  "data": null
}
```

### 狀態碼
- `200` - 成功
- `201` - 創建成功
- `400` - 錯誤請求
- `401` - 未授權
- `404` - 未找到
- `500` - 伺服器錯誤

---

## 🔧 iOS API Service 使用範例

### 認證
```swift
// 登入
let response = try await AuthService.shared.login(
    provider: "apple",
    token: "your_token"
)

// 獲取個人資料
let user = try await AuthService.shared.getProfile()

// 更新個人資料
let updatedUser = try await AuthService.shared.updateProfile(
    name: "新名字",
    height: 175,
    targetWeight: 75,
    weeklyGoal: 4
)
```

### 體重記錄
```swift
// 獲取記錄
let records = try await BodyWeightService.shared.getBodyWeights()

// 創建記錄
let newRecord = try await BodyWeightService.shared.createBodyWeight(
    weight: 77.5,
    date: Date()
)

// 刪除記錄
try await BodyWeightService.shared.deleteBodyWeight(id: "record_id")
```

### 動作
```swift
// 獲取動作列表
let exercises = try await ExerciseService.shared.getExercises()

// 獲取動作詳情
let exercise = try await ExerciseService.shared.getExercise(id: "exercise_id")

// 創建自訂動作
let newExercise = try await ExerciseService.shared.createExercise(
    name: "自訂動作",
    category: "chest",
    equipment: "dumbbell",
    primaryMuscles: ["chest"]
)
```

### 訓練
```swift
// 開始訓練
let workout = try await WorkoutService.shared.startWorkout(name: "今日訓練")

// 添加動作
let workoutExercise = try await WorkoutService.shared.addExercise(
    workoutId: workout.id,
    exerciseId: "exercise_id",
    orderIndex: 0
)

// 添加組數
let set = try await WorkoutService.shared.addSet(
    workoutId: workout.id,
    exerciseId: workoutExercise.id,
    setNumber: 1,
    weight: 100,
    reps: 10
)

// 結束訓練
let completedWorkout = try await WorkoutService.shared.endWorkout(
    id: workout.id,
    notes: "訓練完成"
)
```

---

## 🐛 常見問題

### 1. iOS App 無法連接後端

**檢查事項**：
- 後端是否正在運行？
- 確認 `APIConfig.swift` 中的 baseURL 正確
- 模擬器可以訪問 localhost
- 檢查防火牆設定

**測試連接**：
```bash
# 在終端測試
curl http://localhost:8080/health
```

### 2. 解析錯誤 (Decoding Error)

**可能原因**：
- API 回應格式與 Swift model 不匹配
- 日期格式問題
- JSON key 命名不一致（使用 CodingKeys 映射）

**解決方案**：
- 檢查 API 實際回應
- 使用 Postman 或 curl 測試
- 添加更詳細的錯誤日誌

### 3. 401 未授權

**原因**：
- JWT token 未設定或過期
- 需要登入

**解決方案**：
```swift
// 先登入獲取 token
let response = try await AuthService.shared.login(...)
// token 會自動儲存到 HTTPClient
```

---

## 📱 下一步：整合 ViewModels

將 Mock 資料替換為真實 API 調用：

```swift
class BodyWeightViewModel: ObservableObject {
    @Published var bodyWeights: [BodyWeight] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func fetchBodyWeights() async {
        isLoading = true
        errorMessage = nil
        
        do {
            bodyWeights = try await BodyWeightService.shared.getBodyWeights()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func addBodyWeight(weight: Double, date: Date) async {
        do {
            let newRecord = try await BodyWeightService.shared.createBodyWeight(
                weight: weight,
                date: date
            )
            bodyWeights.insert(newRecord, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

---

## 🎉 測試完整流程

1. **啟動後端**
   ```bash
   cd backend && make run
   ```

2. **運行 iOS App** (Xcode)

3. **測試功能**：
   - ✅ 登入
   - ✅ 查看體重記錄
   - ✅ 添加體重記錄
   - ✅ 查看動作列表
   - ✅ 開始訓練
   - ✅ 添加動作和組數
   - ✅ 查看訓練歷史

4. **檢查後端日誌**
   - 查看 API 請求日誌
   - 確認資料正確傳遞

---

需要幫助？查看：
- 後端 README: `backend/README.md`
- iOS HOW_TO_RUN: `ios/HOW_TO_RUN.md`
- API 文檔: `docs/API_ENDPOINTS.md`

