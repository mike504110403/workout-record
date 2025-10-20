package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// BodyWeight 體重記錄
type BodyWeight struct {
	ID         string    `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	UserID     string    `gorm:"type:uuid;not null;index" json:"user_id"`
	User       User      `gorm:"foreignKey:UserID;constraint:OnDelete:CASCADE" json:"-"`
	Weight     float64   `gorm:"type:decimal(5,2);not null" json:"weight"`       // kg
	BodyFat    *float64  `gorm:"type:decimal(5,2)" json:"body_fat,omitempty"`    // 體脂率 %
	MuscleMass *float64  `gorm:"type:decimal(5,2)" json:"muscle_mass,omitempty"` // 肌肉量 kg
	Notes      *string   `gorm:"type:text" json:"notes,omitempty"`
	Date       time.Time `gorm:"type:date;not null;index" json:"date"`
	CreatedAt  time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt  time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

// BeforeCreate GORM hook
func (b *BodyWeight) BeforeCreate(tx *gorm.DB) error {
	if b.ID == "" {
		b.ID = uuid.New().String()
	}
	return nil
}
