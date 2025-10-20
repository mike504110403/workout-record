# WorkoutRecord iOS App

健身記錄 iOS 應用程式

## 🚀 快速開始

### 1. 打開專案

```bash
open WorkoutRecord/WorkoutRecord.xcodeproj
```

或直接雙擊 `WorkoutRecord/WorkoutRecord.xcodeproj`

### 2. 運行 App

在 Xcode 中：
1. 選擇模擬器（如 iPhone 17）
2. 按 `Cmd + R` 運行

## 📁 專案結構

```
ios/
├── WorkoutRecord/                    # Xcode 專案
│   ├── WorkoutRecord.xcodeproj/     # Xcode 專案文件
│   └── WorkoutRecord/               # 源碼目錄
│       ├── Assets.xcassets/         # 資源文件
│       └── Sources/                 # Swift 源碼
│           ├── Models/              # 數據模型
│           ├── Views/               # UI 視圖
│           ├── ViewModels/          # ViewModel
│           ├── Services/            # API 服務
│           ├── Utils/               # 工具類
│           ├── Data/                # Mock 數據
│           └── WorkoutRecordApp.swift
└── README.md
```

## 🎯 主要功能

### 已實現（Mock 數據）
- ✅ 儀表板：訓練統計、體重記錄、近期訓練
- ✅ 訓練記錄：記錄動作、組數、次數、重量
- ✅ 訓練歷史：查看過去的訓練記錄
- ✅ 統計圖表：訓練量趨勢、肌群分佈
- ✅ 體重記錄：記錄和查看體重變化

### 待整合
- ⏳ 後端 API 整合
- ⏳ 用戶登入（Apple、Google）
- ⏳ 雲端數據同步

## 🔧 技術棧

- **語言**：Swift 5.9+
- **最低版本**：iOS 16.0+
- **UI 框架**：SwiftUI
- **圖表**：Swift Charts（內建）
- **響應式**：Combine

## 📝 開發說明

### 構建
```bash
# Clean Build
Cmd + Shift + K

# Build
Cmd + B

# Run
Cmd + R
```

### 當前狀態
- 🟢 使用 Mock 數據運行
- 🟡 API 服務層已準備好，待整合後端
- 🟡 登入功能待實現

## 🔗 相關資源

- [後端 API 文檔](../backend/README.md)
- [API 端點說明](../backend/API.md)

## 📱 截圖

（待添加）

---

**當前版本**：v0.1.0 (開發中)
