package api

import (
	"encoding/json"
	"net/http"
	"sort"
	"time"

	"workout-record-backend/internal/dto"
	"workout-record-backend/internal/mock"
	"workout-record-backend/internal/models"

	"github.com/gin-gonic/gin"
)

// WorkoutHandler 訓練 Handler
type WorkoutHandler struct{}

// NewWorkoutHandler 創建 WorkoutHandler
func NewWorkoutHandler() *WorkoutHandler {
	return &WorkoutHandler{}
}

// StartWorkout 開始訓練
// @Summary 開始新的訓練
// @Tags Workout
// @Accept json
// @Produce json
// @Param body body dto.WorkoutStartRequest true "開始訓練請求"
// @Success 201 {object} dto.Response{data=models.Workout}
// @Router /api/v1/workouts [post]
func (h *WorkoutHandler) StartWorkout(c *gin.Context) {
	var req dto.WorkoutStartRequest
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

	workout := &models.Workout{
		UserID:    userID,
		Name:      req.Name,
		StartTime: req.StartTime,
		Exercises: []models.WorkoutExercise{},
	}

	mock.GlobalStore.CreateWorkout(workout)

	c.JSON(http.StatusCreated, dto.CreatedResponse(workout, "Workout started"))
}

// EndWorkout 結束訓練
// @Summary 結束訓練
// @Tags Workout
// @Param id path string true "訓練 ID"
// @Param body body dto.WorkoutEndRequest true "結束訓練請求"
// @Success 200 {object} dto.Response{data=models.Workout}
// @Router /api/v1/workouts/{id}/end [put]
func (h *WorkoutHandler) EndWorkout(c *gin.Context) {
	id := c.Param("id")

	var req dto.WorkoutEndRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, dto.BadRequestResponse("Invalid request: "+err.Error()))
		return
	}

	workout := mock.GlobalStore.GetWorkoutByID(id)
	if workout == nil {
		c.JSON(http.StatusNotFound, dto.NotFoundResponse("Workout not found"))
		return
	}

	endTime := time.Now()
	if req.EndTime != nil {
		endTime = *req.EndTime
	}

	workout.EndTime = &endTime
	workout.Duration = int(endTime.Sub(workout.StartTime).Seconds())
	workout.Notes = req.Notes

	mock.GlobalStore.UpdateWorkout(workout)

	c.JSON(http.StatusOK, dto.SuccessResponse(workout, "Workout ended"))
}

// AddExerciseToWorkout 添加動作到訓練
// @Summary 添加動作到訓練
// @Tags Workout
// @Param id path string true "訓練 ID"
// @Param body body dto.AddExerciseRequest true "添加動作請求"
// @Success 200 {object} dto.Response{data=models.WorkoutExercise}
// @Router /api/v1/workouts/{id}/exercises [post]
func (h *WorkoutHandler) AddExerciseToWorkout(c *gin.Context) {
	workoutID := c.Param("id")

	var req dto.AddExerciseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, dto.BadRequestResponse("Invalid request: "+err.Error()))
		return
	}

	workout := mock.GlobalStore.GetWorkoutByID(workoutID)
	if workout == nil {
		c.JSON(http.StatusNotFound, dto.NotFoundResponse("Workout not found"))
		return
	}

	exercise := mock.GlobalStore.GetExerciseByID(req.ExerciseID)
	if exercise == nil {
		c.JSON(http.StatusNotFound, dto.NotFoundResponse("Exercise not found"))
		return
	}

	// 反序列化 exercise muscles
	if exercise.PrimaryMuscles != "" {
		json.Unmarshal([]byte(exercise.PrimaryMuscles), &exercise.PrimaryMusclesArray)
	}
	if exercise.SecondaryMuscles != "" {
		json.Unmarshal([]byte(exercise.SecondaryMuscles), &exercise.SecondaryMusclesArray)
	}

	workoutExercise := models.WorkoutExercise{
		WorkoutID:  workoutID,
		ExerciseID: req.ExerciseID,
		Exercise:   *exercise,
		OrderIndex: req.OrderIndex,
		Sets:       []models.WorkoutSet{},
	}

	mock.GlobalStore.CreateWorkoutExercise(&workoutExercise)

	// 更新 workout
	workout.Exercises = append(workout.Exercises, workoutExercise)
	workout.TotalExercises = len(workout.Exercises)
	mock.GlobalStore.UpdateWorkout(workout)

	c.JSON(http.StatusCreated, dto.CreatedResponse(workoutExercise, "Exercise added"))
}

// AddSetToExercise 添加組數
// @Summary 添加組數到動作
// @Tags Workout
// @Param id path string true "訓練 ID"
// @Param exercise_id path string true "訓練動作 ID"
// @Param body body dto.AddSetRequest true "添加組數請求"
// @Success 201 {object} dto.Response{data=models.WorkoutSet}
// @Router /api/v1/workouts/{id}/exercises/{exercise_id}/sets [post]
func (h *WorkoutHandler) AddSetToExercise(c *gin.Context) {
	workoutID := c.Param("id")
	exerciseID := c.Param("exercise_id")

	var req dto.AddSetRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, dto.BadRequestResponse("Invalid request: "+err.Error()))
		return
	}

	workout := mock.GlobalStore.GetWorkoutByID(workoutID)
	if workout == nil {
		c.JSON(http.StatusNotFound, dto.NotFoundResponse("Workout not found"))
		return
	}

	workoutExercise := mock.GlobalStore.GetWorkoutExercise(exerciseID)
	if workoutExercise == nil {
		c.JSON(http.StatusNotFound, dto.NotFoundResponse("Workout exercise not found"))
		return
	}

	// 計算 volume
	volume := req.Weight * float64(req.Reps)

	workoutSet := models.WorkoutSet{
		WorkoutExerciseID: exerciseID,
		SetNumber:         req.SetNumber,
		Weight:            req.Weight,
		Reps:              req.Reps,
		Volume:            volume,
		RPE:               req.RPE,
		IsWarmup:          req.IsWarmup,
		RestTime:          req.RestTime,
		Notes:             req.Notes,
	}

	mock.GlobalStore.CreateWorkoutSet(&workoutSet)

	// 更新動作統計
	workoutExercise.Sets = append(workoutExercise.Sets, workoutSet)
	workoutExercise.TotalSets = len(workoutExercise.Sets)

	// 更新動作總容量（排除熱身組）
	if !req.IsWarmup {
		workoutExercise.TotalVolume += volume
	}

	// 重新計算訓練總計
	workout.TotalSets = 0
	workout.TotalVolume = 0
	for i := range workout.Exercises {
		if workout.Exercises[i].ID == exerciseID {
			workout.Exercises[i] = *workoutExercise
		}
		workout.TotalSets += workout.Exercises[i].TotalSets
		workout.TotalVolume += workout.Exercises[i].TotalVolume
	}

	mock.GlobalStore.UpdateWorkout(workout)

	c.JSON(http.StatusCreated, dto.CreatedResponse(workoutSet, "Set added"))
}

// ListWorkouts 獲取訓練列表
// @Summary 獲取訓練歷史列表
// @Tags Workout
// @Produce json
// @Success 200 {object} dto.Response{data=dto.WorkoutListResponse}
// @Router /api/v1/workouts [get]
func (h *WorkoutHandler) ListWorkouts(c *gin.Context) {
	// Mock - 獲取測試用戶 ID
	var userID string
	for id := range mock.GlobalStore.Users {
		userID = id
		break
	}

	workouts := mock.GlobalStore.GetUserWorkouts(userID)

	// 按日期排序（最新的在前）
	sort.Slice(workouts, func(i, j int) bool {
		return workouts[i].StartTime.After(workouts[j].StartTime)
	})

	// 轉換為摘要格式
	var summaries []dto.WorkoutSummary
	for _, w := range workouts {
		exerciseNames := []string{}
		for _, ex := range w.Exercises {
			exerciseNames = append(exerciseNames, ex.Exercise.Name)
		}

		summary := dto.WorkoutSummary{
			ID:             w.ID,
			Name:           w.Name,
			Date:           w.StartTime,
			Duration:       w.Duration,
			TotalVolume:    w.TotalVolume,
			TotalSets:      w.TotalSets,
			TotalExercises: w.TotalExercises,
			ExerciseNames:  exerciseNames,
		}
		summaries = append(summaries, summary)
	}

	response := dto.WorkoutListResponse{
		Workouts: summaries,
		Total:    len(summaries),
	}

	c.JSON(http.StatusOK, dto.SuccessResponse(response))
}

// GetWorkout 獲取訓練詳情
// @Summary 獲取訓練詳情
// @Tags Workout
// @Param id path string true "訓練 ID"
// @Success 200 {object} dto.Response{data=models.Workout}
// @Router /api/v1/workouts/{id} [get]
func (h *WorkoutHandler) GetWorkout(c *gin.Context) {
	id := c.Param("id")

	workout := mock.GlobalStore.GetWorkoutByID(id)
	if workout == nil {
		c.JSON(http.StatusNotFound, dto.NotFoundResponse("Workout not found"))
		return
	}

	// 載入完整的 exercises 和 sets 資料
	var fullExercises []models.WorkoutExercise
	for _, ex := range workout.Exercises {
		we := mock.GlobalStore.WorkoutExercises[ex.ID]
		if we != nil {
			// 反序列化 exercise muscles
			if we.Exercise.PrimaryMuscles != "" {
				json.Unmarshal([]byte(we.Exercise.PrimaryMuscles), &we.Exercise.PrimaryMusclesArray)
			}
			if we.Exercise.SecondaryMuscles != "" {
				json.Unmarshal([]byte(we.Exercise.SecondaryMuscles), &we.Exercise.SecondaryMusclesArray)
			}
			fullExercises = append(fullExercises, *we)
		}
	}
	workout.Exercises = fullExercises

	c.JSON(http.StatusOK, dto.SuccessResponse(workout))
}
