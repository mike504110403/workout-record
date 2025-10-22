# Firebase 依賴管理

## 📦 需要添加的 Firebase SDK

### 1. 使用 Swift Package Manager 添加依賴

在 Xcode 中：
1. 選擇專案 → Package Dependencies
2. 點擊 "+" 按鈕
3. 輸入 Firebase 網址：`https://github.com/firebase/firebase-ios-sdk`
4. 選擇以下套件：

#### 必需的套件：
- ✅ **FirebaseAnalytics** - 分析功能
- ✅ **FirebaseFirestore** - 數據庫功能
- ✅ **FirebaseCore** - 核心功能

#### 可選的套件：
- 🔄 **FirebaseAuth** - 身份驗證（未來使用）
- 🔄 **FirebaseStorage** - 文件儲存（未來使用）
- 🔄 **FirebaseCrashlytics** - 崩潰報告（未來使用）

### 📋 添加步驟：
1. 在 Xcode 中選擇 File → Add Packages
2. 輸入網址：`https://github.com/firebase/firebase-ios-sdk`
3. 選擇最新版本
4. 選擇上述必需的程式庫
5. 點擊 Finish

### 2. 手動添加依賴（如果 SPM 不可用）

在 `Package.swift` 中添加：
```swift
dependencies: [
    .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "10.0.0")
],
targets: [
    .target(
        name: "WorkoutRecord",
        dependencies: [
            .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
            .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
            .product(name: "FirebaseCore", package: "firebase-ios-sdk")
        ]
    )
]
```

## 🔧 配置步驟

### 1. 下載 GoogleService-Info.plist
- 從 Firebase Console 下載
- 拖拽到 Xcode 專案中
- 確保 Bundle ID 為 `com.mikelin.workitout`

### 2. 在 App 中初始化 Firebase
```swift
import FirebaseCore

@main
struct WorkoutRecordApp: App {
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        // App 內容
    }
}
```

### 3. 設定 Firestore 安全規則
複製 `FirebaseSecurityRules.swift` 中的規則到 Firebase Console

## 📋 檢查清單

- [ ] 添加 Firebase SDK 依賴
- [ ] 下載 GoogleService-Info.plist
- [ ] 在 App 中初始化 Firebase
- [ ] 設定 Firestore 安全規則
- [ ] 測試 Firebase 連接
- [ ] 驗證數據上傳功能

## 🚨 常見問題

### 1. 編譯錯誤
- 確保所有 Firebase 套件版本一致
- 檢查 Bundle ID 是否正確

### 2. 連接失敗
- 檢查 GoogleService-Info.plist 是否正確添加
- 確認 Firebase 專案設定正確

### 3. 權限錯誤
- 檢查 Firestore 安全規則
- 確認規則已發布
