package api

import (
	"net/http"
	"time"

	"workout-record-backend/internal/dto"
	"workout-record-backend/internal/mock"
	"workout-record-backend/internal/models"

	"github.com/gin-gonic/gin"
)

// AuthHandler 認證相關 Handler
type AuthHandler struct{}

// NewAuthHandler 創建 AuthHandler
func NewAuthHandler() *AuthHandler {
	return &AuthHandler{}
}

// Login 登入
// @Summary 用戶登入
// @Tags Auth
// @Accept json
// @Produce json
// @Param body body dto.LoginRequest true "登入請求"
// @Success 200 {object} dto.Response{data=dto.LoginResponse}
// @Router /api/v1/auth/login [post]
func (h *AuthHandler) Login(c *gin.Context) {
	var req dto.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, dto.BadRequestResponse("Invalid request: "+err.Error()))
		return
	}

	// Mock 驗證邏輯 - 實際應該驗證 Apple/Google token
	// 這裡暫時創建或獲取測試用戶
	email := "test@example.com"
	user := mock.GlobalStore.GetUserByEmail(email)

	if user == nil {
		// 創建新用戶
		user = &models.User{
			Email: email,
			Name:  "測試用戶",
		}
		mock.GlobalStore.CreateUser(user)
	}

	// Mock JWT token - 實際應該生成真實的 JWT
	mockToken := "mock_jwt_token_" + user.ID

	response := dto.LoginResponse{
		Token: mockToken,
		User:  *user,
	}

	c.JSON(http.StatusOK, dto.SuccessResponse(response, "Login successful"))
}

// GetProfile 獲取用戶資料
// @Summary 獲取當前用戶資料
// @Tags Auth
// @Produce json
// @Success 200 {object} dto.Response{data=models.User}
// @Router /api/v1/auth/profile [get]
func (h *AuthHandler) GetProfile(c *gin.Context) {
	// Mock - 從 context 獲取用戶 ID（實際應該從 JWT 解析）
	userID := c.GetString("user_id")
	if userID == "" {
		// 使用默認測試用戶
		for _, user := range mock.GlobalStore.Users {
			c.JSON(http.StatusOK, dto.SuccessResponse(user))
			return
		}
	}

	user := mock.GlobalStore.Users[userID]
	if user == nil {
		c.JSON(http.StatusNotFound, dto.NotFoundResponse("User not found"))
		return
	}

	c.JSON(http.StatusOK, dto.SuccessResponse(user))
}

// UpdateProfile 更新用戶資料
// @Summary 更新用戶資料
// @Tags Auth
// @Accept json
// @Produce json
// @Param body body dto.UserProfileUpdateRequest true "更新請求"
// @Success 200 {object} dto.Response{data=models.User}
// @Router /api/v1/auth/profile [put]
func (h *AuthHandler) UpdateProfile(c *gin.Context) {
	var req dto.UserProfileUpdateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, dto.BadRequestResponse("Invalid request: "+err.Error()))
		return
	}

	// Mock - 獲取測試用戶
	var user *models.User
	for _, u := range mock.GlobalStore.Users {
		user = u
		break
	}

	if user == nil {
		c.JSON(http.StatusNotFound, dto.NotFoundResponse("User not found"))
		return
	}

	// 更新欄位
	if req.Name != nil {
		user.Name = *req.Name
	}
	if req.Height != nil {
		user.Height = req.Height
	}
	if req.TargetWeight != nil {
		user.TargetWeight = req.TargetWeight
	}
	if req.WeeklyGoal != nil {
		user.WeeklyGoal = req.WeeklyGoal
	}
	user.UpdatedAt = time.Now()

	c.JSON(http.StatusOK, dto.SuccessResponse(user, "Profile updated successfully"))
}
