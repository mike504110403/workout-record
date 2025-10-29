package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// User 用戶模型
type User struct {
	ID           string    `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	Email        string    `gorm:"type:varchar(255);uniqueIndex;not null" json:"email"`
	Name         string    `gorm:"type:varchar(100);not null" json:"name"`
	Height       *float64  `gorm:"type:decimal(5,2)" json:"height,omitempty"`        // cm
	TargetWeight *float64  `gorm:"type:decimal(5,2)" json:"target_weight,omitempty"` // kg
	WeeklyGoal   *int      `gorm:"type:integer" json:"weekly_goal,omitempty"`        // 每週訓練目標次數
	CreatedAt    time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt    time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

// BeforeCreate GORM hook - 在創建前生成 UUID
func (u *User) BeforeCreate(tx *gorm.DB) error {
	if u.ID == "" {
		u.ID = uuid.New().String()
	}
	return nil
}
