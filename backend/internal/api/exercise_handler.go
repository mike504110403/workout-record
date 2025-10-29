package api

import (
	"encoding/json"
	"net/http"

	"workout-record-backend/internal/dto"
	"workout-record-backend/internal/mock"
	"workout-record-backend/internal/models"

	"github.com/gin-gonic/gin"
)

// ExerciseHandler 動作 Handler
type ExerciseHandler struct{}

// NewExerciseHandler 創建 ExerciseHandler
func NewExerciseHandler() *ExerciseHandler {
	return &ExerciseHandler{}
}

// ListExercises 獲取動作列表
// @Summary 獲取動作列表
// @Tags Exercise
// @Produce json
// @Param category query string false "分類篩選"
// @Param equipment query string false "器材篩選"
// @Success 200 {object} dto.Response{data=dto.ExerciseListResponse}
// @Router /api/v1/exercises [get]
func (h *ExerciseHandler) ListExercises(c *gin.Context) {
	category := c.Query("category")
	equipment := c.Query("equipment")

	exercises := mock.GlobalStore.GetAllExercises()

	// 篩選
	var filtered []*models.Exercise
	for _, ex := range exercises {
		if category != "" && ex.Category != category {
			continue
		}
		if equipment != "" && ex.Equipment != equipment {
			continue
		}

		// 反序列化 JSON 字串到陣列
		if ex.PrimaryMuscles != "" {
			json.Unmarshal([]byte(ex.PrimaryMuscles), &ex.PrimaryMusclesArray)
		}
		if ex.SecondaryMuscles != "" {
			json.Unmarshal([]byte(ex.SecondaryMuscles), &ex.SecondaryMusclesArray)
		}

		filtered = append(filtered, ex)
	}

	// 轉換為非指針切片
	var result []models.Exercise
	for _, ex := range filtered {
		result = append(result, *ex)
	}

	response := dto.ExerciseListResponse{
		Exercises: result,
		Total:     len(result),
	}

	c.JSON(http.StatusOK, dto.SuccessResponse(response))
}

// GetExercise 獲取單個動作
// @Summary 獲取動作詳情
// @Tags Exercise
// @Param id path string true "動作 ID"
// @Success 200 {object} dto.Response{data=models.Exercise}
// @Router /api/v1/exercises/{id} [get]
func (h *ExerciseHandler) GetExercise(c *gin.Context) {
	id := c.Param("id")

	exercise := mock.GlobalStore.GetExerciseByID(id)
	if exercise == nil {
		c.JSON(http.StatusNotFound, dto.NotFoundResponse("Exercise not found"))
		return
	}

	// 反序列化 JSON
	if exercise.PrimaryMuscles != "" {
		json.Unmarshal([]byte(exercise.PrimaryMuscles), &exercise.PrimaryMusclesArray)
	}
	if exercise.SecondaryMuscles != "" {
		json.Unmarshal([]byte(exercise.SecondaryMuscles), &exercise.SecondaryMusclesArray)
	}

	c.JSON(http.StatusOK, dto.SuccessResponse(exercise))
}

// CreateExercise 創建自訂動作
// @Summary 創建自訂動作
// @Tags Exercise
// @Accept json
// @Produce json
// @Param body body dto.ExerciseCreateRequest true "創建請求"
// @Success 201 {object} dto.Response{data=models.Exercise}
// @Router /api/v1/exercises [post]
func (h *ExerciseHandler) CreateExercise(c *gin.Context) {
	var req dto.ExerciseCreateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, dto.BadRequestResponse("Invalid request: "+err.Error()))
		return
	}

	// Mock - 獲取測試用戶 ID
	var userID string
	for id := range mock.GlobalStore.Users {
		userID = id
		break
	}

	// 序列化陣列為 JSON
	primaryJSON, _ := json.Marshal(req.PrimaryMuscles)
	secondaryJSON, _ := json.Marshal(req.SecondaryMuscles)

	exercise := &models.Exercise{
		Name:                  req.Name,
		NameEn:                req.NameEn,
		Category:              req.Category,
		Equipment:             req.Equipment,
		PrimaryMuscles:        string(primaryJSON),
		PrimaryMusclesArray:   req.PrimaryMuscles,
		SecondaryMuscles:      string(secondaryJSON),
		SecondaryMusclesArray: req.SecondaryMuscles,
		IsCustom:              true,
		UserID:                &userID,
	}

	mock.GlobalStore.CreateExercise(exercise)

	c.JSON(http.StatusCreated, dto.CreatedResponse(exercise, "Exercise created"))
}
