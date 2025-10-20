package dto

import "workout-record-backend/internal/models"

// LoginRequest 登入請求
type LoginRequest struct {
	Provider string `json:"provider" binding:"required"` // "apple" or "google"
	Token    string `json:"token" binding:"required"`
}

// LoginResponse 登入回應
type LoginResponse struct {
	Token string      `json:"token"`
	User  models.User `json:"user"`
}

// UserProfileUpdateRequest 用戶個人資料更新請求
type UserProfileUpdateRequest struct {
	Name         *string  `json:"name,omitempty"`
	Height       *float64 `json:"height,omitempty"`
	TargetWeight *float64 `json:"target_weight,omitempty"`
	WeeklyGoal   *int     `json:"weekly_goal,omitempty"`
}
