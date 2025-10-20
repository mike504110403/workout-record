package dto

import (
	"time"
	"workout-record-backend/internal/models"
)

// BodyWeightCreateRequest 新增體重記錄請求
type BodyWeightCreateRequest struct {
	Weight     float64   `json:"weight" binding:"required"`
	BodyFat    *float64  `json:"body_fat,omitempty"`
	MuscleMass *float64  `json:"muscle_mass,omitempty"`
	Notes      *string   `json:"notes,omitempty"`
	Date       time.Time `json:"date" binding:"required"`
}

// BodyWeightUpdateRequest 更新體重記錄請求
type BodyWeightUpdateRequest struct {
	Weight     *float64   `json:"weight,omitempty"`
	BodyFat    *float64   `json:"body_fat,omitempty"`
	MuscleMass *float64   `json:"muscle_mass,omitempty"`
	Notes      *string    `json:"notes,omitempty"`
	Date       *time.Time `json:"date,omitempty"`
}

// BodyWeightListResponse 體重記錄列表回應
type BodyWeightListResponse struct {
	Records []models.BodyWeight `json:"records"`
	Total   int                 `json:"total"`
}
