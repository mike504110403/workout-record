#!/bin/bash

# 健身記錄 API 後端啟動腳本

echo "🚀 啟動 Workout Record API..."

# 檢查端口是否被佔用
if lsof -Pi :8080 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "⚠️  端口 8080 已被佔用"
    echo "是否要終止佔用端口的進程？(y/n)"
    read -r answer
    if [ "$answer" = "y" ]; then
        lsof -ti:8080 | xargs kill -9 2>/dev/null
        echo "✅ 端口已清理"
        sleep 1
    else
        echo "❌ 取消啟動"
        exit 1
    fi
fi

# 啟動服務器
echo "🌐 啟動服務器..."
go run cmd/server/main.go

