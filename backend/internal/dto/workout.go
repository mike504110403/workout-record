package dto

import (
	"time"
	"workout-record-backend/internal/models"
)

// WorkoutStartRequest 開始訓練請求
type WorkoutStartRequest struct {
	Name      *string   `json:"name,omitempty"`
	StartTime time.Time `json:"start_time" binding:"required"`
}

// WorkoutEndRequest 結束訓練請求
type WorkoutEndRequest struct {
	EndTime *time.Time `json:"end_time,omitempty"`
	Notes   *string    `json:"notes,omitempty"`
}

// WorkoutUpdateRequest 更新訓練請求
type WorkoutUpdateRequest struct {
	Name  *string `json:"name,omitempty"`
	Notes *string `json:"notes,omitempty"`
}

// AddExerciseRequest 添加動作到訓練請求
type AddExerciseRequest struct {
	ExerciseID string `json:"exercise_id" binding:"required"`
	OrderIndex int    `json:"order_index"`
}

// AddSetRequest 添加組數請求
type AddSetRequest struct {
	SetNumber int      `json:"set_number" binding:"required"`
	Weight    float64  `json:"weight" binding:"required"`
	Reps      int      `json:"reps" binding:"required"`
	RPE       *float64 `json:"rpe,omitempty"`
	IsWarmup  bool     `json:"is_warmup"`
	RestTime  *int     `json:"rest_time,omitempty"`
	Notes     *string  `json:"notes,omitempty"`
}

// UpdateSetRequest 更新組數請求
type UpdateSetRequest struct {
	Weight   *float64 `json:"weight,omitempty"`
	Reps     *int     `json:"reps,omitempty"`
	RPE      *float64 `json:"rpe,omitempty"`
	IsWarmup *bool    `json:"is_warmup,omitempty"`
	RestTime *int     `json:"rest_time,omitempty"`
	Notes    *string  `json:"notes,omitempty"`
}

// WorkoutSummary 訓練摘要（用於列表）
type WorkoutSummary struct {
	ID             string    `json:"id"`
	Name           *string   `json:"name,omitempty"`
	Date           time.Time `json:"date"`
	Duration       int       `json:"duration"`
	TotalVolume    float64   `json:"total_volume"`
	TotalSets      int       `json:"total_sets"`
	TotalExercises int       `json:"total_exercises"`
	ExerciseNames  []string  `json:"exercise_names"`
}

// WorkoutListResponse 訓練列表回應
type WorkoutListResponse struct {
	Workouts []WorkoutSummary `json:"workouts"`
	Total    int              `json:"total"`
}

// VolumeDataPoint 容量資料點（用於圖表）
type VolumeDataPoint struct {
	Date   time.Time `json:"date"`
	Volume float64   `json:"volume"`
}

// VolumeStatsResponse 容量統計回應
type VolumeStatsResponse struct {
	DataPoints  []VolumeDataPoint `json:"data_points"`
	TotalVolume float64           `json:"total_volume"`
	AvgVolume   float64           `json:"avg_volume"`
}

// MuscleGroupData 肌群分布資料
type MuscleGroupData struct {
	MuscleGroup string  `json:"muscle_group"`
	Volume      float64 `json:"volume"`
	Percentage  float64 `json:"percentage"`
}

// MuscleGroupStatsResponse 肌群統計回應
type MuscleGroupStatsResponse struct {
	Distribution []MuscleGroupData `json:"distribution"`
	Period       string            `json:"period"` // week, month, year
}

// WorkoutDetailResponse 訓練詳情回應（完整資料）
type WorkoutDetailResponse struct {
	Workout models.Workout `json:"workout"`
}
