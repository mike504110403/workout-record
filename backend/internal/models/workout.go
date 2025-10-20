package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// Workout 訓練記錄
type Workout struct {
	ID             string            `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	UserID         string            `gorm:"type:uuid;not null;index" json:"user_id"`
	User           User              `gorm:"foreignKey:UserID;constraint:OnDelete:CASCADE" json:"-"`
	Name           *string           `gorm:"type:varchar(100)" json:"name,omitempty"`
	StartTime      time.Time         `gorm:"type:timestamp;not null;index" json:"start_time"`
	EndTime        *time.Time        `gorm:"type:timestamp" json:"end_time,omitempty"`
	Duration       int               `gorm:"type:integer;default:0" json:"duration"`           // 秒
	TotalVolume    float64           `gorm:"type:decimal(10,2);default:0" json:"total_volume"` // kg
	TotalSets      int               `gorm:"type:integer;default:0" json:"total_sets"`
	TotalExercises int               `gorm:"type:integer;default:0" json:"total_exercises"`
	Notes          *string           `gorm:"type:text" json:"notes,omitempty"`
	Exercises      []WorkoutExercise `gorm:"foreignKey:WorkoutID;constraint:OnDelete:CASCADE" json:"exercises"`
	CreatedAt      time.Time         `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt      time.Time         `gorm:"autoUpdateTime" json:"updated_at"`
}

// WorkoutExercise 訓練中的動作
type WorkoutExercise struct {
	ID           string       `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	WorkoutID    string       `gorm:"type:uuid;not null;index" json:"workout_id"`
	Workout      Workout      `gorm:"foreignKey:WorkoutID;constraint:OnDelete:CASCADE" json:"-"`
	ExerciseID   string       `gorm:"type:uuid;not null;index" json:"exercise_id"`
	Exercise     Exercise     `gorm:"foreignKey:ExerciseID" json:"exercise"`
	OrderIndex   int          `gorm:"type:integer;not null;default:0" json:"order_index"`
	TotalVolume  float64      `gorm:"type:decimal(10,2);default:0" json:"total_volume"` // 該動作的總容量
	TotalSets    int          `gorm:"type:integer;default:0" json:"total_sets"`
	PersonalBest bool         `gorm:"type:boolean;default:false" json:"personal_best"` // 是否為 PR
	Sets         []WorkoutSet `gorm:"foreignKey:WorkoutExerciseID;constraint:OnDelete:CASCADE" json:"sets"`
	CreatedAt    time.Time    `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt    time.Time    `gorm:"autoUpdateTime" json:"updated_at"`
}

// WorkoutSet 單組記錄
type WorkoutSet struct {
	ID                string          `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	WorkoutExerciseID string          `gorm:"type:uuid;not null;index" json:"workout_exercise_id"`
	WorkoutExercise   WorkoutExercise `gorm:"foreignKey:WorkoutExerciseID;constraint:OnDelete:CASCADE" json:"-"`
	SetNumber         int             `gorm:"type:integer;not null" json:"set_number"`
	Weight            float64         `gorm:"type:decimal(6,2);not null" json:"weight"` // kg
	Reps              int             `gorm:"type:integer;not null" json:"reps"`
	Volume            float64         `gorm:"type:decimal(10,2);not null" json:"volume"` // weight * reps
	RPE               *float64        `gorm:"type:decimal(3,1)" json:"rpe,omitempty"`    // Rate of Perceived Exertion (6-10)
	IsWarmup          bool            `gorm:"type:boolean;default:false" json:"is_warmup"`
	RestTime          *int            `gorm:"type:integer" json:"rest_time,omitempty"` // 秒
	Notes             *string         `gorm:"type:text" json:"notes,omitempty"`
	CreatedAt         time.Time       `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt         time.Time       `gorm:"autoUpdateTime" json:"updated_at"`
}

// BeforeCreate hooks
func (w *Workout) BeforeCreate(tx *gorm.DB) error {
	if w.ID == "" {
		w.ID = uuid.New().String()
	}
	return nil
}

func (we *WorkoutExercise) BeforeCreate(tx *gorm.DB) error {
	if we.ID == "" {
		we.ID = uuid.New().String()
	}
	return nil
}

func (ws *WorkoutSet) BeforeCreate(tx *gorm.DB) error {
	if ws.ID == "" {
		ws.ID = uuid.New().String()
	}
	// 自動計算 volume
	if ws.Volume == 0 {
		ws.Volume = ws.Weight * float64(ws.Reps)
	}
	return nil
}
