package api

import (
	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
)

// SetupRouter 設定路由
func SetupRouter() *gin.Engine {
	r := gin.Default()

	// CORS 設定
	config := cors.DefaultConfig()
	config.AllowOrigins = []string{"*"} // 開發階段允許所有來源
	config.AllowMethods = []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"}
	config.AllowHeaders = []string{"Origin", "Content-Type", "Authorization"}
	r.Use(cors.New(config))

	// 健康檢查
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"code":    200,
			"message": "Server is running",
			"data": gin.H{
				"status": "healthy",
			},
		})
	})

	// API v1
	v1 := r.Group("/api/v1")
	{
		// Auth 路由
		authHandler := NewAuthHandler()
		auth := v1.Group("/auth")
		{
			auth.POST("/login", authHandler.Login)
			auth.GET("/profile", authHandler.GetProfile)
			auth.PUT("/profile", authHandler.UpdateProfile)
		}

		// Body Weight 路由
		bwHandler := NewBodyWeightHandler()
		bodyWeights := v1.Group("/body-weights")
		{
			bodyWeights.GET("", bwHandler.ListBodyWeights)
			bodyWeights.POST("", bwHandler.CreateBodyWeight)
			bodyWeights.DELETE("/:id", bwHandler.DeleteBodyWeight)
		}

		// Exercise 路由
		exHandler := NewExerciseHandler()
		exercises := v1.Group("/exercises")
		{
			exercises.GET("", exHandler.ListExercises)
			exercises.GET("/:id", exHandler.GetExercise)
			exercises.POST("", exHandler.CreateExercise)
		}

		// Workout 路由
		workoutHandler := NewWorkoutHandler()
		workouts := v1.Group("/workouts")
		{
			workouts.GET("", workoutHandler.ListWorkouts)
			workouts.POST("", workoutHandler.StartWorkout)
			workouts.GET("/:id", workoutHandler.GetWorkout)
			workouts.PUT("/:id/end", workoutHandler.EndWorkout)
			workouts.POST("/:id/exercises", workoutHandler.AddExerciseToWorkout)
			workouts.POST("/:id/exercises/:exercise_id/sets", workoutHandler.AddSetToExercise)
		}
	}

	return r
}
