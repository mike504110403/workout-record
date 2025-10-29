#!/bin/bash

# 截圖尺寸調整腳本
# 將 1320x2868 調整為 1284x2778

echo "📸 開始調整截圖尺寸..."

# 創建輸出目錄
mkdir -p ~/Desktop/WorkitOut_Resized

# 找到所有桌面上的截圖
for file in ~/Desktop/Simulator*.png; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        echo "處理: $filename"
        
        # 使用 sips 調整尺寸（Mac 內建工具）
        sips -z 2778 1284 "$file" --out ~/Desktop/WorkitOut_Resized/"$filename"
        
        echo "✅ 已調整: $filename"
    fi
done

echo ""
echo "🎉 完成！調整後的截圖在："
echo "~/Desktop/WorkitOut_Resized/"
echo ""
echo "原始尺寸: 1320 × 2868"
echo "新尺寸: 1284 × 2778"

