.PHONY: run build test clean help

# 默認目標
.DEFAULT_GOAL := help

# 運行開發伺服器
run:
	@echo "🚀 Starting development server..."
	@go run cmd/server/main.go

# 編譯
build:
	@echo "🔨 Building..."
	@go build -o bin/server cmd/server/main.go
	@echo "✅ Build complete: bin/server"

# 運行測試
test:
	@echo "🧪 Running tests..."
	@go test -v ./...

# 安裝依賴
deps:
	@echo "📦 Installing dependencies..."
	@go mod download
	@go mod tidy

# 清理
clean:
	@echo "🧹 Cleaning..."
	@rm -rf bin/
	@rm -f *.log
	@echo "✅ Clean complete"

# 格式化程式碼
fmt:
	@echo "💅 Formatting code..."
	@go fmt ./...

# 檢查程式碼
lint:
	@echo "🔍 Linting..."
	@go vet ./...

# 幫助
help:
	@echo "Available commands:"
	@echo "  make run    - Run development server"
	@echo "  make build  - Build binary"
	@echo "  make test   - Run tests"
	@echo "  make deps   - Install dependencies"
	@echo "  make clean  - Clean build files"
	@echo "  make fmt    - Format code"
	@echo "  make lint   - Lint code"

