package api

import (
	"net/http"
	"sort"

	"workout-record-backend/internal/dto"
	"workout-record-backend/internal/mock"
	"workout-record-backend/internal/models"

	"github.com/gin-gonic/gin"
)

// BodyWeightHandler 體重記錄 Handler
type BodyWeightHandler struct{}

// NewBodyWeightHandler 創建 BodyWeightHandler
func NewBodyWeightHandler() *BodyWeightHandler {
	return &BodyWeightHandler{}
}

// ListBodyWeights 獲取體重記錄列表
// @Summary 獲取體重記錄列表
// @Tags BodyWeight
// @Produce json
// @Success 200 {object} dto.Response{data=dto.BodyWeightListResponse}
// @Router /api/v1/body-weights [get]
func (h *BodyWeightHandler) ListBodyWeights(c *gin.Context) {
	// Mock - 獲取測試用戶的體重記錄
	var userID string
	for id := range mock.GlobalStore.Users {
		userID = id
		break
	}

	records := mock.GlobalStore.GetUserBodyWeights(userID)

	// 按日期排序（最新的在前）
	sort.Slice(records, func(i, j int) bool {
		return records[i].Date.After(records[j].Date)
	})

	// 轉換為非指針切片
	var result []models.BodyWeight
	for _, r := range records {
		result = append(result, *r)
	}

	response := dto.BodyWeightListResponse{
		Records: result,
		Total:   len(result),
	}

	c.JSON(http.StatusOK, dto.SuccessResponse(response))
}

// CreateBodyWeight 創建體重記錄
// @Summary 創建體重記錄
// @Tags BodyWeight
// @Accept json
// @Produce json
// @Param body body dto.BodyWeightCreateRequest true "創建請求"
// @Success 201 {object} dto.Response{data=models.BodyWeight}
// @Router /api/v1/body-weights [post]
func (h *BodyWeightHandler) CreateBodyWeight(c *gin.Context) {
	var req dto.BodyWeightCreateRequest
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

	bodyWeight := &models.BodyWeight{
		UserID:     userID,
		Weight:     req.Weight,
		BodyFat:    req.BodyFat,
		MuscleMass: req.MuscleMass,
		Notes:      req.Notes,
		Date:       req.Date,
	}

	mock.GlobalStore.CreateBodyWeight(bodyWeight)

	c.JSON(http.StatusCreated, dto.CreatedResponse(bodyWeight, "Body weight record created"))
}

// DeleteBodyWeight 刪除體重記錄
// @Summary 刪除體重記錄
// @Tags BodyWeight
// @Param id path string true "體重記錄 ID"
// @Success 200 {object} dto.Response
// @Router /api/v1/body-weights/{id} [delete]
func (h *BodyWeightHandler) DeleteBodyWeight(c *gin.Context) {
	id := c.Param("id")

	if !mock.GlobalStore.DeleteBodyWeight(id) {
		c.JSON(http.StatusNotFound, dto.NotFoundResponse("Body weight record not found"))
		return
	}

	c.JSON(http.StatusOK, dto.SuccessResponse(nil, "Body weight record deleted"))
}
