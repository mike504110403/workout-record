package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// Exercise 動作模型
type Exercise struct {
	ID                    string    `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	Name                  string    `gorm:"type:varchar(100);not null;index" json:"name"`
	NameEn                string    `gorm:"type:varchar(100);index" json:"name_en,omitempty"`
	Category              string    `gorm:"type:varchar(50);not null;index" json:"category"`   // 分類：chest, back, legs, etc.
	Equipment             string    `gorm:"type:varchar(50);not null;index" json:"equipment"`  // 器材：barbell, dumbbell, machine, etc.
	PrimaryMuscles        string    `gorm:"type:text;not null" json:"-"`                       // 儲存為 JSON 字串
	PrimaryMusclesArray   []string  `gorm:"-" json:"primary_muscles"`                          // API 使用
	SecondaryMuscles      string    `gorm:"type:text" json:"-"`                                // 儲存為 JSON 字串
	SecondaryMusclesArray []string  `gorm:"-" json:"secondary_muscles,omitempty"`              // API 使用
	IsCustom              bool      `gorm:"type:boolean;default:false;index" json:"is_custom"` // 是否為用戶自訂
	UserID                *string   `gorm:"type:uuid;index" json:"user_id,omitempty"`          // 自訂動作的用戶ID
	User                  *User     `gorm:"foreignKey:UserID;constraint:OnDelete:CASCADE" json:"-"`
	CreatedAt             time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt             time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

// BeforeCreate GORM hook
func (e *Exercise) BeforeCreate(tx *gorm.DB) error {
	if e.ID == "" {
		e.ID = uuid.New().String()
	}
	return nil
}
