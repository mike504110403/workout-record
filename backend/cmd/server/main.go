package main

import (
	"log"
	"os"

	"workout-record-backend/internal/api"
	"workout-record-backend/internal/mock"
)

func main() {
	log.Println("🚀 Starting Workout Record API Server...")

	// 初始化 Mock 資料儲存
	mock.InitStore()
	log.Println("✅ Mock data store initialized")

	// 設定路由
	router := api.SetupRouter()

	// 獲取端口
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("🌐 Server is running on http://localhost:%s\n", port)
	log.Printf("📡 Health check: http://localhost:%s/health\n", port)
	log.Printf("📚 API Base URL: http://localhost:%s/api/v1\n", port)

	// 啟動伺服器
	if err := router.Run(":" + port); err != nil {
		log.Fatal("Failed to start server:", err)
	}
}
