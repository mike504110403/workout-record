# API Endpoints 文件

**Base URL**: `/api/v1`

**認證方式**: Bearer Token (JWT)

---

## 認證相關 API

### POST /auth/login/apple
Apple Sign In 登入

**Request Body:**
```json
{
  "identity_token": "eyJra...",
  "authorization_code": "c1234...",
  "user_info": {
    "name": "張三",
    "email": "user@example.com"
  }
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "access_token": "eyJhbGc...",
    "refresh_token": "eyJhbGc...",
    "expires_in": 3600,
    "user": {
      "id": "uuid",
      "email": "user@example.com",
      "name": "張三"
    }
  }
}
```

### POST /auth/login/google
Google Sign In 登入

**Request Body:**
```json
{
  "id_token": "eyJhbGc..."
}
```

**Response:** 同 Apple Sign In

### POST /auth/refresh
刷新 Token

**Request Body:**
```json
{
  "refresh_token": "eyJhbGc..."
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "access_token": "eyJhbGc...",
    "expires_in": 3600
  }
}
```

### POST /auth/logout
登出

**Headers:** `Authorization: Bearer <token>`

**Response:**
```json
{
  "success": true,
  "message": "登出成功"
}
```

---

## 用戶相關 API

### GET /users/me
取得當前用戶資訊

**Headers:** `Authorization: Bearer <token>`

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "email": "user@example.com",
    "name": "張三",
    "avatar_url": "https://...",
    "height": 175.0,
    "gender": "male",
    "birth_date": "1990-01-01",
    "target_weight": 70.0,
    "weekly_workout_goal": 4,
    "preferred_unit": "kg",
    "preferred_1rm_formula": "epley",
    "created_at": "2025-01-01T00:00:00Z"
  }
}
```

### PUT /users/me
更新當前用戶資訊

**Headers:** `Authorization: Bearer <token>`

**Request Body:**
```json
{
  "name": "張三",
  "height": 175.0,
  "target_weight": 70.0,
  "weekly_workout_goal": 5,
  "preferred_unit": "kg",
  "preferred_1rm_formula": "brzycki"
}
```

**Response:** 同 GET /users/me

### DELETE /users/me
刪除當前用戶帳號

**Headers:** `Authorization: Bearer <token>`

**Response:**
```json
{
  "success": true,
  "message": "帳號已刪除"
}
```

---

## 體重記錄 API

### GET /body-weights
取得體重記錄列表

**Headers:** `Authorization: Bearer <token>`

**Query Parameters:**
- `start_date` (optional): 開始日期 (ISO 8601)
- `end_date` (optional): 結束日期 (ISO 8601)
- `limit` (optional, default: 100): 每頁筆數
- `offset` (optional, default: 0): 偏移量

**Response:**
```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "uuid",
        "weight": 75.5,
        "measured_at": "2025-10-20T08:00:00Z",
        "note": "早上測量",
        "created_at": "2025-10-20T08:00:00Z"
      }
    ],
    "total": 100,
    "limit": 100,
    "offset": 0
  }
}
```

### POST /body-weights
新增體重記錄

**Headers:** `Authorization: Bearer <token>`

**Request Body:**
```json
{
  "weight": 75.5,
  "measured_at": "2025-10-20T08:00:00Z",
  "note": "早上測量"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "weight": 75.5,
    "measured_at": "2025-10-20T08:00:00Z",
    "note": "早上測量",
    "created_at": "2025-10-20T08:00:00Z"
  }
}
```

### PUT /body-weights/:id
更新體重記錄

**Headers:** `Authorization: Bearer <token>`

**Request Body:** 同 POST

**Response:** 同 POST

### DELETE /body-weights/:id
刪除體重記錄

**Headers:** `Authorization: Bearer <token>`

**Response:**
```json
{
  "success": true,
  "message": "刪除成功"
}
```

---

## 動作庫 API

### GET /exercise-categories
取得動作分類列表

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "uuid",
      "name": "胸部",
      "name_en": "Chest",
      "display_order": 1
    }
  ]
}
```

### GET /exercises
取得動作列表

**Query Parameters:**
- `category_id` (optional): 分類 ID
- `type` (optional): 動作類型 (machine/free_weight/bodyweight)
- `search` (optional): 搜尋關鍵字
- `is_favorite` (optional): 是否只顯示常用
- `include_hidden` (optional, default: false): 是否包含隱藏動作

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "uuid",
      "name": "槓鈴臥推",
      "name_en": "Barbell Bench Press",
      "category": {
        "id": "uuid",
        "name": "胸部"
      },
      "type": "free_weight",
      "muscle_group": ["胸大肌", "三角肌前束", "肱三頭肌"],
      "description": "...",
      "video_url": "https://...",
      "image_url": "https://...",
      "is_system": true,
      "user_settings": {
        "is_favorite": true,
        "is_hidden": false
      }
    }
  ]
}
```

### GET /exercises/:id
取得單一動作詳情

**Response:** 同上單一項目

### POST /exercises
新增自定義動作

**Headers:** `Authorization: Bearer <token>`

**Request Body:**
```json
{
  "name": "自定義臥推",
  "category_id": "uuid",
  "type": "free_weight",
  "muscle_group": ["胸大肌"],
  "description": "...",
  "video_url": "https://...",
  "image_url": "https://..."
}
```

**Response:** 同 GET /exercises/:id

### PUT /exercises/:id
更新自定義動作

**Headers:** `Authorization: Bearer <token>`

**Request Body:** 同 POST

**Response:** 同 POST

### DELETE /exercises/:id
刪除自定義動作

**Headers:** `Authorization: Bearer <token>`

**Response:**
```json
{
  "success": true,
  "message": "刪除成功"
}
```

---

## 用戶動作設定 API

### GET /user-exercise-settings
取得用戶動作設定

**Headers:** `Authorization: Bearer <token>`

**Query Parameters:**
- `exercise_id` (optional): 特定動作 ID

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "exercise_id": "uuid",
      "is_favorite": true,
      "is_hidden": false,
      "custom_order": 1
    }
  ]
}
```

### PUT /user-exercise-settings/:exercise_id
更新單一動作設定

**Headers:** `Authorization: Bearer <token>`

**Request Body:**
```json
{
  "is_favorite": true,
  "is_hidden": false,
  "custom_order": 1
}
```

**Response:** 同 GET

### POST /user-exercise-settings/batch
批量更新動作設定

**Headers:** `Authorization: Bearer <token>`

**Request Body:**
```json
{
  "settings": [
    {
      "exercise_id": "uuid",
      "is_favorite": true
    }
  ]
}
```

**Response:**
```json
{
  "success": true,
  "message": "批量更新成功"
}
```

---

## 訓練記錄 API

### GET /workouts
取得訓練記錄列表

**Headers:** `Authorization: Bearer <token>`

**Query Parameters:**
- `start_date` (optional): 開始日期
- `end_date` (optional): 結束日期
- `limit` (optional, default: 20): 每頁筆數
- `offset` (optional, default: 0): 偏移量

**Response:**
```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "uuid",
        "started_at": "2025-10-20T10:00:00Z",
        "ended_at": "2025-10-20T11:30:00Z",
        "duration": 90,
        "total_volume": 5000.0,
        "total_sets": 20,
        "total_exercises": 5,
        "note": "今天狀態不錯",
        "exercises_summary": [
          {
            "exercise_name": "臥推",
            "sets": 4
          }
        ]
      }
    ],
    "total": 50,
    "limit": 20,
    "offset": 0
  }
}
```

### GET /workouts/:id
取得單一訓練詳情

**Headers:** `Authorization: Bearer <token>`

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "started_at": "2025-10-20T10:00:00Z",
    "ended_at": "2025-10-20T11:30:00Z",
    "duration": 90,
    "total_volume": 5000.0,
    "total_sets": 20,
    "total_exercises": 5,
    "note": "今天狀態不錯",
    "exercises": [
      {
        "id": "uuid",
        "exercise": {
          "id": "uuid",
          "name": "臥推",
          "category": "胸部"
        },
        "order_index": 1,
        "total_volume": 2000.0,
        "total_sets": 4,
        "sets": [
          {
            "id": "uuid",
            "set_number": 1,
            "weight": 100.0,
            "reps": 10,
            "volume": 1000.0,
            "rpe": 8.0,
            "rest_seconds": 120,
            "is_warmup": false,
            "note": ""
          }
        ]
      }
    ]
  }
}
```

### POST /workouts
新增訓練記錄

**Headers:** `Authorization: Bearer <token>`

**Request Body:**
```json
{
  "started_at": "2025-10-20T10:00:00Z",
  "ended_at": "2025-10-20T11:30:00Z",
  "note": "今天狀態不錯",
  "template_id": "uuid",
  "exercises": [
    {
      "exercise_id": "uuid",
      "order_index": 1,
      "note": "",
      "sets": [
        {
          "set_number": 1,
          "weight": 100.0,
          "reps": 10,
          "rpe": 8.0,
          "rest_seconds": 120,
          "is_warmup": false,
          "note": ""
        }
      ]
    }
  ]
}
```

**Response:** 同 GET /workouts/:id

### PUT /workouts/:id
更新訓練記錄

**Headers:** `Authorization: Bearer <token>`

**Request Body:** 同 POST

**Response:** 同 POST

### DELETE /workouts/:id
刪除訓練記錄

**Headers:** `Authorization: Bearer <token>`

**Response:**
```json
{
  "success": true,
  "message": "刪除成功"
}
```

---

## 訓練動作/組數 API (用於細部操作)

### POST /workout-exercises
新增動作到訓練

**Headers:** `Authorization: Bearer <token>`

**Request Body:**
```json
{
  "workout_id": "uuid",
  "exercise_id": "uuid",
  "order_index": 1
}
```

### PUT /workout-exercises/:id
更新訓練動作

### DELETE /workout-exercises/:id
刪除訓練動作

### POST /workout-sets
新增組數

**Request Body:**
```json
{
  "workout_exercise_id": "uuid",
  "set_number": 1,
  "weight": 100.0,
  "reps": 10,
  "rpe": 8.0,
  "is_warmup": false
}
```

### PUT /workout-sets/:id
更新組數

### DELETE /workout-sets/:id
刪除組數

---

## 訓練模板 API

### GET /workout-templates
取得訓練模板列表

**Headers:** `Authorization: Bearer <token>`

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "uuid",
      "name": "胸背日",
      "description": "PPL - Push Day",
      "is_system": false,
      "exercises_count": 6
    }
  ]
}
```

### GET /workout-templates/:id
取得模板詳情

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "name": "胸背日",
    "description": "PPL - Push Day",
    "is_system": false,
    "exercises": [
      {
        "exercise": {
          "id": "uuid",
          "name": "臥推"
        },
        "order_index": 1,
        "suggested_sets": 4,
        "suggested_reps": 10,
        "note": "重量訓練"
      }
    ]
  }
}
```

### POST /workout-templates
新增訓練模板

**Request Body:**
```json
{
  "name": "胸背日",
  "description": "PPL - Push Day",
  "exercises": [
    {
      "exercise_id": "uuid",
      "order_index": 1,
      "suggested_sets": 4,
      "suggested_reps": 10,
      "note": ""
    }
  ]
}
```

### PUT /workout-templates/:id
更新訓練模板

### DELETE /workout-templates/:id
刪除訓練模板

---

## 個人記錄 API

### GET /personal-records
取得個人記錄列表

**Headers:** `Authorization: Bearer <token>`

**Query Parameters:**
- `exercise_id` (optional): 特定動作
- `record_type` (optional): 記錄類型 (1rm/max_weight/max_reps/max_volume)

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "uuid",
      "exercise": {
        "id": "uuid",
        "name": "臥推"
      },
      "record_type": "max_weight",
      "value": 120.0,
      "reps": 5,
      "achieved_at": "2025-10-15T10:30:00Z"
    }
  ]
}
```

### GET /personal-records/exercise/:exercise_id
取得特定動作的所有記錄

### GET /personal-records/top
取得 PR 排行榜

**Query Parameters:**
- `limit` (optional, default: 10)
- `record_type` (optional)

---

## 統計分析 API ⭐

### GET /stats/dashboard
取得 Dashboard 統計資料

**Headers:** `Authorization: Bearer <token>`

**Response:**
```json
{
  "success": true,
  "data": {
    "today": {
      "workout_completed": true,
      "total_volume": 5000.0,
      "duration": 90,
      "exercises": 5
    },
    "this_week": {
      "workout_count": 4,
      "total_volume": 18000.0,
      "avg_volume_per_workout": 4500.0,
      "total_duration": 360
    },
    "current_weight": 75.5,
    "recent_workouts": [...]
  }
}
```

### GET /stats/body-weight-trend
體重趨勢

**Query Parameters:**
- `period`: week/month/quarter/year/custom
- `start_date` (if period=custom)
- `end_date` (if period=custom)

**Response:**
```json
{
  "success": true,
  "data": {
    "trend": [
      {
        "date": "2025-10-01",
        "weight": 76.0
      }
    ],
    "statistics": {
      "current": 75.5,
      "average": 75.8,
      "max": 76.5,
      "min": 75.0,
      "change": -1.0,
      "change_percentage": -1.3
    }
  }
}
```

### GET /stats/workout-frequency
訓練頻率統計

**Query Parameters:**
- `period`: week/month/quarter/year

**Response:**
```json
{
  "success": true,
  "data": {
    "frequency": [
      {
        "date": "2025-10-14",
        "count": 1
      }
    ],
    "statistics": {
      "total_workouts": 16,
      "avg_per_week": 4.0,
      "current_streak": 5
    }
  }
}
```

### GET /stats/volume-trend ⭐
訓練容量趨勢

**Query Parameters:**
- `period`: week/month/quarter/year/custom
- `start_date`, `end_date` (if custom)
- `group_by`: day/week/month

**Response:**
```json
{
  "success": true,
  "data": {
    "trend": [
      {
        "date": "2025-10-20",
        "total_volume": 5000.0,
        "workout_count": 1,
        "avg_volume": 5000.0
      }
    ],
    "statistics": {
      "total_volume": 20000.0,
      "avg_volume": 5000.0,
      "max_volume": 6000.0,
      "min_volume": 4000.0,
      "trend": "increasing",
      "change_percentage": 12.5
    }
  }
}
```

### GET /stats/volume-by-exercise/:exercise_id ⭐
特定動作容量趨勢

**Query Parameters:**
- `period`: week/month/quarter/year

**Response:**
```json
{
  "success": true,
  "data": {
    "exercise": {
      "id": "uuid",
      "name": "臥推"
    },
    "trend": [
      {
        "date": "2025-10-20",
        "volume": 2000.0,
        "sets": 4,
        "max_weight": 100.0,
        "avg_reps": 10
      }
    ],
    "statistics": {
      "total_volume": 8000.0,
      "avg_volume": 2000.0,
      "max_volume": 2400.0,
      "total_workouts": 4
    }
  }
}
```

### GET /stats/volume-by-muscle-group ⭐
肌群容量分布

**Query Parameters:**
- `period`: week/month/quarter/year

**Response:**
```json
{
  "success": true,
  "data": {
    "distribution": [
      {
        "muscle_group": "胸",
        "total_volume": 5000.0,
        "percentage": 25.0,
        "workout_count": 3
      }
    ],
    "total_volume": 20000.0
  }
}
```

### GET /stats/volume-comparison ⭐
容量週期對比

**Query Parameters:**
- `period`: week/month/quarter
- `compare_to`: previous/last_year

**Response:**
```json
{
  "success": true,
  "data": {
    "current": {
      "period": "2025-W42",
      "total_volume": 18000.0,
      "workout_count": 4
    },
    "previous": {
      "period": "2025-W41",
      "total_volume": 16000.0,
      "workout_count": 4
    },
    "comparison": {
      "volume_change": 2000.0,
      "volume_change_percentage": 12.5,
      "workout_count_change": 0
    }
  }
}
```

---

## 後台管理 API

### POST /admin/exercises
批量新增動作

**Headers:** `Authorization: Bearer <admin_token>`

**Request Body:**
```json
{
  "exercises": [
    {
      "name": "槓鈴臥推",
      "name_en": "Barbell Bench Press",
      "category_id": "uuid",
      "type": "free_weight",
      "muscle_group": ["胸大肌", "三角肌前束"],
      "description": "..."
    }
  ]
}
```

### GET /admin/stats/system
系統統計

**Response:**
```json
{
  "success": true,
  "data": {
    "total_users": 1000,
    "active_users_today": 150,
    "total_workouts": 50000,
    "total_exercises": 120
  }
}
```

---

## 通用回應格式

### 成功回應
```json
{
  "success": true,
  "data": {...},
  "message": "操作成功"
}
```

### 錯誤回應
```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "錯誤訊息",
    "details": {...}
  }
}
```

### 常見錯誤碼
- `UNAUTHORIZED`: 未授權
- `FORBIDDEN`: 無權限
- `NOT_FOUND`: 資源不存在
- `VALIDATION_ERROR`: 資料驗證錯誤
- `INTERNAL_ERROR`: 伺服器錯誤

---

最後更新: 2025-10-20

