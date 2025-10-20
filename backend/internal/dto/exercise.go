package dto

import "workout-record-backend/internal/models"

// ExerciseCreateRequest 新增動作請求
type ExerciseCreateRequest struct {
	Name             string   `json:"name" binding:"required"`
	NameEn           string   `json:"name_en,omitempty"`
	Category         string   `json:"category" binding:"required"`
	Equipment        string   `json:"equipment" binding:"required"`
	PrimaryMuscles   []string `json:"primary_muscles" binding:"required"`
	SecondaryMuscles []string `json:"secondary_muscles,omitempty"`
}

// ExerciseUpdateRequest 更新動作請求
type ExerciseUpdateRequest struct {
	Name             *string  `json:"name,omitempty"`
	NameEn           *string  `json:"name_en,omitempty"`
	Category         *string  `json:"category,omitempty"`
	Equipment        *string  `json:"equipment,omitempty"`
	PrimaryMuscles   []string `json:"primary_muscles,omitempty"`
	SecondaryMuscles []string `json:"secondary_muscles,omitempty"`
}

// ExerciseListResponse 動作列表回應
type ExerciseListResponse struct {
	Exercises []models.Exercise `json:"exercises"`
	Total     int               `json:"total"`
}
