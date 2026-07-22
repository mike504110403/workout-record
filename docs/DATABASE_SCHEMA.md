# 資料庫設計 (PostgreSQL)

## Schema 概覽

```
users (用戶)
├── body_weights (體重記錄)
├── exercises (動作庫) - 自定義動作
├── user_exercise_settings (用戶動作設定)
├── workouts (訓練記錄)
├── workout_templates (訓練模板)
└── personal_records (個人記錄)

exercise_categories (動作分類) - 系統
└── exercises (動作庫) - 預設動作

workouts (訓練記錄)
└── workout_exercises (訓練動作)
    └── workout_sets (訓練組數)

workout_templates (訓練模板)
└── workout_template_exercises (模板動作)
```

---

## 資料表定義

### users (用戶表)
```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    apple_id VARCHAR(255) UNIQUE,
    google_id VARCHAR(255) UNIQUE,
    name VARCHAR(100),
    avatar_url VARCHAR(500),
    height DECIMAL(5,2),                    -- 身高 (cm)
    gender VARCHAR(10),                     -- 性別
    birth_date DATE,                        -- 生日
    target_weight DECIMAL(5,2),             -- 目標體重 (kg)
    weekly_workout_goal INT,                -- 每週訓練目標次數
    preferred_unit VARCHAR(10) DEFAULT 'kg',-- 偏好單位 (kg/lb)
    preferred_1rm_formula VARCHAR(20) DEFAULT 'epley', -- 偏好 1RM 公式
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_apple_id ON users(apple_id);
CREATE INDEX idx_users_google_id ON users(google_id);
```

---

### body_weights (體重記錄表)
```sql
CREATE TABLE body_weights (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    weight DECIMAL(5,2) NOT NULL,           -- 體重 (kg)
    measured_at TIMESTAMP NOT NULL,         -- 測量時間
    note TEXT,                              -- 備註
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_body_weights_user_id ON body_weights(user_id);
CREATE INDEX idx_body_weights_measured_at ON body_weights(measured_at);
CREATE INDEX idx_body_weights_user_date ON body_weights(user_id, measured_at DESC);
```

---

### exercise_categories (動作分類表)
```sql
CREATE TABLE exercise_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(50) NOT NULL,              -- 分類名稱 (胸/背/腿/肩/手臂/核心)
    name_en VARCHAR(50),                    -- 英文名稱
    display_order INT DEFAULT 0,            -- 顯示順序
    is_system BOOLEAN DEFAULT true,         -- 是否為系統預設
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_exercise_categories_display_order ON exercise_categories(display_order);
```

---

### exercises (動作庫表)
```sql
CREATE TABLE exercises (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,             -- 動作名稱
    name_en VARCHAR(100),                   -- 英文名稱
    category_id UUID NOT NULL REFERENCES exercise_categories(id),
    type VARCHAR(20) NOT NULL,              -- 'machine'/'free_weight'/'bodyweight'
    muscle_group VARCHAR(100)[],            -- 目標肌群（陣列）
    description TEXT,                       -- 動作說明
    video_url VARCHAR(500),                 -- 影片連結
    image_url VARCHAR(500),                 -- 圖片連結
    is_system BOOLEAN DEFAULT true,         -- 是否為系統預設
    user_id UUID REFERENCES users(id) ON DELETE CASCADE, -- 自定義動作的創建者
    is_active BOOLEAN DEFAULT true,         -- 是否啟用
    display_order INT DEFAULT 0,            -- 顯示順序
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_exercises_category_id ON exercises(category_id);
CREATE INDEX idx_exercises_type ON exercises(type);
CREATE INDEX idx_exercises_is_system ON exercises(is_system);
CREATE INDEX idx_exercises_user_id ON exercises(user_id);
CREATE INDEX idx_exercises_name ON exercises(name);
```

---

### user_exercise_settings (用戶動作設定表)
```sql
CREATE TABLE user_exercise_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
    is_hidden BOOLEAN DEFAULT false,        -- 是否隱藏
    is_favorite BOOLEAN DEFAULT false,      -- 是否為常用
    custom_order INT,                       -- 自訂排序
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(user_id, exercise_id)
);

CREATE INDEX idx_user_exercise_settings_user_id ON user_exercise_settings(user_id);
CREATE INDEX idx_user_exercise_settings_exercise_id ON user_exercise_settings(exercise_id);
CREATE INDEX idx_user_exercise_settings_favorite ON user_exercise_settings(user_id, is_favorite);
```

---

### workouts (訓練記錄表)
```sql
CREATE TABLE workouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    started_at TIMESTAMP NOT NULL,          -- 開始時間
    ended_at TIMESTAMP,                     -- 結束時間
    duration INT,                           -- 訓練時長（分鐘）
    total_volume DECIMAL(10,2) DEFAULT 0,   -- 總訓練容量 (kg) ⭐
    total_sets INT DEFAULT 0,               -- 總組數 ⭐
    total_exercises INT DEFAULT 0,          -- 總動作數 ⭐
    note TEXT,                              -- 訓練備註
    template_id UUID REFERENCES workout_templates(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_workouts_user_id ON workouts(user_id);
CREATE INDEX idx_workouts_started_at ON workouts(started_at);
CREATE INDEX idx_workouts_user_date ON workouts(user_id, started_at DESC);
CREATE INDEX idx_workouts_template_id ON workouts(template_id);
```

---

### workout_exercises (訓練動作記錄表)
```sql
CREATE TABLE workout_exercises (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workout_id UUID NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES exercises(id),
    order_index INT NOT NULL,               -- 動作順序
    total_volume DECIMAL(10,2) DEFAULT 0,   -- 該動作總容量 (kg) ⭐
    total_sets INT DEFAULT 0,               -- 總組數 ⭐
    note TEXT,                              -- 動作備註
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_workout_exercises_workout_id ON workout_exercises(workout_id);
CREATE INDEX idx_workout_exercises_exercise_id ON workout_exercises(exercise_id);
CREATE INDEX idx_workout_exercises_order ON workout_exercises(workout_id, order_index);
```

---

### workout_sets (訓練組數記錄表)
```sql
CREATE TABLE workout_sets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workout_exercise_id UUID NOT NULL REFERENCES workout_exercises(id) ON DELETE CASCADE,
    set_number INT NOT NULL,                -- 組數編號
    weight DECIMAL(6,2) NOT NULL,           -- 重量 (kg)
    reps INT NOT NULL,                      -- 次數
    volume DECIMAL(10,2) NOT NULL,          -- 本組容量 = weight × reps ⭐
    rpe DECIMAL(3,1),                       -- RPE 等級 (1-10)
    rest_seconds INT,                       -- 休息時間（秒）
    is_warmup BOOLEAN DEFAULT false,        -- 是否為暖身組
    note TEXT,                              -- 組數備註
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_workout_sets_workout_exercise_id ON workout_sets(workout_exercise_id);
CREATE INDEX idx_workout_sets_set_number ON workout_sets(workout_exercise_id, set_number);
```

---

### workout_templates (訓練模板表)
```sql
CREATE TABLE workout_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,             -- 模板名稱
    description TEXT,                       -- 模板說明
    is_system BOOLEAN DEFAULT false,        -- 是否為系統預設
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_workout_templates_user_id ON workout_templates(user_id);
CREATE INDEX idx_workout_templates_is_system ON workout_templates(is_system);
```

---

### workout_template_exercises (訓練模板動作表)
```sql
CREATE TABLE workout_template_exercises (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id UUID NOT NULL REFERENCES workout_templates(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES exercises(id),
    order_index INT NOT NULL,               -- 動作順序
    suggested_sets INT,                     -- 建議組數
    suggested_reps INT,                     -- 建議次數
    note TEXT,                              -- 動作備註
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_workout_template_exercises_template_id ON workout_template_exercises(template_id);
CREATE INDEX idx_workout_template_exercises_order ON workout_template_exercises(template_id, order_index);
```

---

### personal_records (個人記錄表)
```sql
CREATE TABLE personal_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES exercises(id),
    record_type VARCHAR(20) NOT NULL,       -- '1rm'/'max_weight'/'max_reps'/'max_volume'
    value DECIMAL(10,2) NOT NULL,           -- 記錄值
    reps INT,                               -- 達成時的次數
    achieved_at TIMESTAMP NOT NULL,         -- 達成時間
    workout_set_id UUID REFERENCES workout_sets(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_personal_records_user_id ON personal_records(user_id);
CREATE INDEX idx_personal_records_exercise_id ON personal_records(exercise_id);
CREATE INDEX idx_personal_records_type ON personal_records(user_id, exercise_id, record_type);
CREATE INDEX idx_personal_records_achieved_at ON personal_records(achieved_at DESC);
```

---

## 容量計算邏輯 ⭐

### 1. 單組容量 (workout_sets.volume)
```
volume = weight × reps
```

### 2. 單一動作總容量 (workout_exercises.total_volume)
```
total_volume = SUM(volume) WHERE is_warmup = false
total_sets = COUNT(*) WHERE is_warmup = false
```

### 3. 單次訓練總容量 (workouts.total_volume)
```
total_volume = SUM(workout_exercises.total_volume)
total_sets = SUM(workout_exercises.total_sets)
total_exercises = COUNT(DISTINCT workout_exercises.id)
```

---

## 資料庫觸發器 (Triggers)

### 自動更新容量
```sql
-- 當新增/更新 workout_sets 時，自動計算 volume
CREATE OR REPLACE FUNCTION calculate_set_volume()
RETURNS TRIGGER AS $$
BEGIN
    NEW.volume := NEW.weight * NEW.reps;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_calculate_set_volume
    BEFORE INSERT OR UPDATE ON workout_sets
    FOR EACH ROW
    EXECUTE FUNCTION calculate_set_volume();

-- 當 workout_sets 變更時，更新 workout_exercises 的總容量
CREATE OR REPLACE FUNCTION update_workout_exercise_totals()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE workout_exercises
    SET 
        total_volume = (
            SELECT COALESCE(SUM(volume), 0)
            FROM workout_sets
            WHERE workout_exercise_id = NEW.workout_exercise_id
            AND is_warmup = false
        ),
        total_sets = (
            SELECT COUNT(*)
            FROM workout_sets
            WHERE workout_exercise_id = NEW.workout_exercise_id
            AND is_warmup = false
        ),
        updated_at = NOW()
    WHERE id = NEW.workout_exercise_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_workout_exercise_totals
    AFTER INSERT OR UPDATE OR DELETE ON workout_sets
    FOR EACH ROW
    EXECUTE FUNCTION update_workout_exercise_totals();

-- 當 workout_exercises 變更時，更新 workouts 的總容量
CREATE OR REPLACE FUNCTION update_workout_totals()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE workouts
    SET 
        total_volume = (
            SELECT COALESCE(SUM(total_volume), 0)
            FROM workout_exercises
            WHERE workout_id = NEW.workout_id
        ),
        total_sets = (
            SELECT COALESCE(SUM(total_sets), 0)
            FROM workout_exercises
            WHERE workout_id = NEW.workout_id
        ),
        total_exercises = (
            SELECT COUNT(*)
            FROM workout_exercises
            WHERE workout_id = NEW.workout_id
        ),
        updated_at = NOW()
    WHERE id = NEW.workout_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_workout_totals
    AFTER INSERT OR UPDATE OR DELETE ON workout_exercises
    FOR EACH ROW
    EXECUTE FUNCTION update_workout_totals();
```

---

## 索引策略

### 主要查詢場景
1. 用戶查詢自己的訓練記錄（按日期排序）
2. 查詢特定動作的歷史記錄
3. 統計特定時間範圍的訓練數據
4. 查詢個人記錄排行

### 複合索引
已在上方各表定義中包含

---

## 預設數據 (Seed Data)

### 動作分類
```
1. 胸 (Chest)
2. 背 (Back)
3. 腿 (Legs)
4. 肩 (Shoulders)
5. 手臂 (Arms)
6. 核心 (Core)
```

### 預設動作（待補充完整列表）
詳見 `docs/DEFAULT_EXERCISES.md`

---

最後更新: 2025-10-20

