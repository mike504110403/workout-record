package mock

import (
	"encoding/json"
	"sync"
	"time"

	"workout-record-backend/internal/models"

	"github.com/google/uuid"
)

// Store Mock 資料儲存（暫時替代資料庫）
type Store struct {
	Users            map[string]*models.User
	BodyWeights      map[string]*models.BodyWeight
	Exercises        map[string]*models.Exercise
	Workouts         map[string]*models.Workout
	WorkoutExercises map[string]*models.WorkoutExercise
	WorkoutSets      map[string]*models.WorkoutSet
	mu               sync.RWMutex
}

var GlobalStore *Store

// InitStore 初始化 Mock 資料儲存
func InitStore() {
	GlobalStore = &Store{
		Users:            make(map[string]*models.User),
		BodyWeights:      make(map[string]*models.BodyWeight),
		Exercises:        make(map[string]*models.Exercise),
		Workouts:         make(map[string]*models.Workout),
		WorkoutExercises: make(map[string]*models.WorkoutExercise),
		WorkoutSets:      make(map[string]*models.WorkoutSet),
	}

	// 初始化假資料
	initMockData()
}

// initMockData 初始化一些假資料
func initMockData() {
	// 創建測試用戶
	userID := uuid.New().String()
	height := 175.0
	targetWeight := 75.0
	weeklyGoal := 4

	user := &models.User{
		ID:           userID,
		Email:        "test@example.com",
		Name:         "測試用戶",
		Height:       &height,
		TargetWeight: &targetWeight,
		WeeklyGoal:   &weeklyGoal,
		CreatedAt:    time.Now(),
		UpdatedAt:    time.Now(),
	}
	GlobalStore.Users[userID] = user

	// 創建一些體重記錄
	for i := 0; i < 30; i++ {
		bwID := uuid.New().String()
		weight := 77.0 + float64(i%5)*0.3
		date := time.Now().AddDate(0, 0, -i)

		bw := &models.BodyWeight{
			ID:        bwID,
			UserID:    userID,
			Weight:    weight,
			Date:      date,
			CreatedAt: date,
			UpdatedAt: date,
		}
		GlobalStore.BodyWeights[bwID] = bw
	}

	// 創建預設動作
	exercises := []struct {
		name      string
		nameEn    string
		category  string
		equipment string
		primary   []string
		secondary []string
	}{
		{"深蹲", "Squat", "legs", "barbell", []string{"quadriceps"}, []string{"glutes", "hamstrings"}},
		{"臥推", "Bench Press", "chest", "barbell", []string{"chest"}, []string{"triceps", "shoulders"}},
		{"硬舉", "Deadlift", "back", "barbell", []string{"back"}, []string{"glutes", "hamstrings"}},
		{"肩推", "Overhead Press", "shoulders", "barbell", []string{"shoulders"}, []string{"triceps"}},
		{"划船", "Barbell Row", "back", "barbell", []string{"back"}, []string{"biceps"}},
	}

	for _, ex := range exercises {
		exID := uuid.New().String()
		primaryJSON, _ := json.Marshal(ex.primary)
		secondaryJSON, _ := json.Marshal(ex.secondary)

		exercise := &models.Exercise{
			ID:                    exID,
			Name:                  ex.name,
			NameEn:                ex.nameEn,
			Category:              ex.category,
			Equipment:             ex.equipment,
			PrimaryMuscles:        string(primaryJSON),
			PrimaryMusclesArray:   ex.primary,
			SecondaryMuscles:      string(secondaryJSON),
			SecondaryMusclesArray: ex.secondary,
			IsCustom:              false,
			CreatedAt:             time.Now(),
			UpdatedAt:             time.Now(),
		}
		GlobalStore.Exercises[exID] = exercise
	}
}

// GetUserByEmail 通過 email 查找用戶
func (s *Store) GetUserByEmail(email string) *models.User {
	s.mu.RLock()
	defer s.mu.RUnlock()

	for _, user := range s.Users {
		if user.Email == email {
			return user
		}
	}
	return nil
}

// CreateUser 創建用戶
func (s *Store) CreateUser(user *models.User) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if user.ID == "" {
		user.ID = uuid.New().String()
	}
	user.CreatedAt = time.Now()
	user.UpdatedAt = time.Now()
	s.Users[user.ID] = user
}

// GetUserBodyWeights 獲取用戶的體重記錄
func (s *Store) GetUserBodyWeights(userID string) []*models.BodyWeight {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var results []*models.BodyWeight
	for _, bw := range s.BodyWeights {
		if bw.UserID == userID {
			results = append(results, bw)
		}
	}
	return results
}

// CreateBodyWeight 創建體重記錄
func (s *Store) CreateBodyWeight(bw *models.BodyWeight) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if bw.ID == "" {
		bw.ID = uuid.New().String()
	}
	bw.CreatedAt = time.Now()
	bw.UpdatedAt = time.Now()
	s.BodyWeights[bw.ID] = bw
}

// GetAllExercises 獲取所有動作
func (s *Store) GetAllExercises() []*models.Exercise {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var results []*models.Exercise
	for _, ex := range s.Exercises {
		results = append(results, ex)
	}
	return results
}

// GetExerciseByID 獲取動作
func (s *Store) GetExerciseByID(id string) *models.Exercise {
	s.mu.RLock()
	defer s.mu.RUnlock()

	return s.Exercises[id]
}

// CreateWorkout 創建訓練
func (s *Store) CreateWorkout(workout *models.Workout) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if workout.ID == "" {
		workout.ID = uuid.New().String()
	}
	workout.CreatedAt = time.Now()
	workout.UpdatedAt = time.Now()
	s.Workouts[workout.ID] = workout
}

// GetWorkoutByID 獲取訓練
func (s *Store) GetWorkoutByID(id string) *models.Workout {
	s.mu.RLock()
	defer s.mu.RUnlock()

	return s.Workouts[id]
}

// UpdateWorkout 更新訓練
func (s *Store) UpdateWorkout(workout *models.Workout) {
	s.mu.Lock()
	defer s.mu.Unlock()

	workout.UpdatedAt = time.Now()
	s.Workouts[workout.ID] = workout
}

// GetUserWorkouts 獲取用戶的訓練記錄
func (s *Store) GetUserWorkouts(userID string) []*models.Workout {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var results []*models.Workout
	for _, w := range s.Workouts {
		if w.UserID == userID {
			results = append(results, w)
		}
	}
	return results
}

// DeleteBodyWeight 刪除體重記錄
func (s *Store) DeleteBodyWeight(id string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, exists := s.BodyWeights[id]; !exists {
		return false
	}
	delete(s.BodyWeights, id)
	return true
}

// CreateExercise 創建動作
func (s *Store) CreateExercise(exercise *models.Exercise) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if exercise.ID == "" {
		exercise.ID = uuid.New().String()
	}
	exercise.CreatedAt = time.Now()
	exercise.UpdatedAt = time.Now()
	s.Exercises[exercise.ID] = exercise
}

// CreateWorkoutExercise 創建訓練動作
func (s *Store) CreateWorkoutExercise(we *models.WorkoutExercise) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if we.ID == "" {
		we.ID = uuid.New().String()
	}
	we.CreatedAt = time.Now()
	we.UpdatedAt = time.Now()
	s.WorkoutExercises[we.ID] = we
}

// CreateWorkoutSet 創建組數記錄
func (s *Store) CreateWorkoutSet(ws *models.WorkoutSet) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if ws.ID == "" {
		ws.ID = uuid.New().String()
	}
	ws.CreatedAt = time.Now()
	ws.UpdatedAt = time.Now()
	// 自動計算 volume
	if ws.Volume == 0 {
		ws.Volume = ws.Weight * float64(ws.Reps)
	}
	s.WorkoutSets[ws.ID] = ws
}

// GetWorkoutExercise 獲取訓練動作
func (s *Store) GetWorkoutExercise(id string) *models.WorkoutExercise {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.WorkoutExercises[id]
}
