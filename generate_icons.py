#!/usr/bin/env python3
"""
生成 App 圖示的 Python 腳本
需要安裝 Pillow: pip install Pillow
"""

from PIL import Image, ImageDraw, ImageFont
import os

def create_app_icon(size, filename):
    """創建指定尺寸的 App 圖示"""
    # 創建不透明背景
    img = Image.new('RGB', (size, size), (102, 126, 234))
    draw = ImageDraw.Draw(img)
    
    # 計算圓角半徑
    corner_radius = size // 6
    
    # 創建圓角矩形背景
    draw.rounded_rectangle(
        [(0, 0), (size, size)],
        radius=corner_radius,
        fill=(102, 126, 234)  # 藍紫色背景
    )
    
    # 繪製啞鈴圖示
    center_x, center_y = size // 2, size // 2
    dumbbell_width = size * 0.6
    dumbbell_height = size * 0.15
    
    # 左側重量片
    left_weight_x = center_x - dumbbell_width // 2
    left_weight_size = size * 0.15
    draw.rounded_rectangle(
        [(left_weight_x, center_y - left_weight_size // 2),
         (left_weight_x + left_weight_size, center_y + left_weight_size // 2)],
        radius=size // 50,
        fill=(255, 107, 107)  # 紅色
    )
    
    # 中間握把
    handle_width = dumbbell_width * 0.6
    handle_height = dumbbell_height
    handle_x = center_x - handle_width // 2
    draw.rounded_rectangle(
        [(handle_x, center_y - handle_height // 2),
         (handle_x + handle_width, center_y + handle_height // 2)],
        radius=size // 25,
        fill=(255, 255, 255)  # 白色
    )
    
    # 右側重量片
    right_weight_x = center_x + dumbbell_width // 2 - left_weight_size
    draw.rounded_rectangle(
        [(right_weight_x, center_y - left_weight_size // 2),
         (right_weight_x + left_weight_size, center_y + left_weight_size // 2)],
        radius=size // 50,
        fill=(255, 107, 107)  # 紅色
    )
    
    # 添加文字 "WR" (僅在較大尺寸時)
    if size >= 60:
        try:
            # 嘗試使用系統字體
            font_size = size // 8
            font = ImageFont.truetype("/System/Library/Fonts/Arial.ttf", font_size)
        except:
            # 如果找不到字體，使用預設字體
            font = ImageFont.load_default()
        
        text = "WR"
        bbox = draw.textbbox((0, 0), text, font=font)
        text_width = bbox[2] - bbox[0]
        text_height = bbox[3] - bbox[1]
        
        text_x = center_x - text_width // 2
        text_y = center_y + size * 0.3
        
        draw.text((text_x, text_y), text, fill=(255, 255, 255), font=font)
    
    # 保存圖片
    img.save(filename, 'PNG')
    print(f"✅ 已生成 {filename} ({size}x{size})")

def main():
    """生成所有需要的圖示尺寸"""
    # 確保輸出目錄存在
    output_dir = "ios/WorkoutRecord/WorkoutRecord/Assets.xcassets/AppIcon.appiconset"
    os.makedirs(output_dir, exist_ok=True)
    
    # 定義所有需要的尺寸
    sizes = [
        (20, "icon-20.png"),
        (40, "icon-20@2x.png"),
        (60, "icon-20@3x.png"),
        (29, "icon-29.png"),
        (58, "icon-29@2x.png"),
        (87, "icon-29@3x.png"),
        (40, "icon-40.png"),
        (80, "icon-40@2x.png"),
        (120, "icon-40@3x.png"),
        (120, "icon-60@2x.png"),
        (180, "icon-60@3x.png"),
        (76, "icon-76.png"),
        (152, "icon-76@2x.png"),
        (167, "icon-83.5@2x.png"),
        (1024, "icon-1024.png")
    ]
    
    print("🎨 開始生成 App 圖示...")
    
    for size, filename in sizes:
        filepath = os.path.join(output_dir, filename)
        create_app_icon(size, filepath)
    
    print("\n🎉 所有圖示已生成完成！")
    print("📁 圖示位置:", output_dir)
    print("\n📋 下一步:")
    print("1. 在 Xcode 中重新 Archive")
    print("2. 上傳到 TestFlight")

if __name__ == "__main__":
    main()
