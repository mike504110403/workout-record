# 🔧 技術實現方案

## 📌 目標
確保 WorkoutRecord App 能夠安全上線，具備版本管理、用戶追蹤、數據遷移能力，並為未來付費功能預留彈性。

---

## 1️⃣ 版本管理與強制更新系統

### 架構設計

```
App 啟動
  ↓
檢查版本
  ↓
從 Firebase Remote Config 獲取
  - minimumVersion (最低支援版本)
  - latestVersion (最新版本)
  - forceUpdate (是否強制更新)
  - updateMessage (更新說明)
  ↓
比對當前版本
  ↓
┌──────────────┬──────────────┬──────────────┐
│ 版本 < 最低   │ 版本 < 最新   │ 版本 = 最新   │
│ 強制更新      │ 可選更新      │ 正常使用      │
└──────────────┴──────────────┴──────────────┘
```

### 文件結構

```swift
// Sources/Services/VersionManager.swift
// Sources/Views/Update/ForceUpdateView.swift
// Sources/Views/Update/OptionalUpdateView.swift
```

### Firebase Remote Config 配置

```json
{
  "ios_minimum_version": "1.0.0",
  "ios_latest_version": "1.0.0",
  "ios_force_update": false,
  "ios_update_message_zh": "新版本包含重要更新，請立即更新",
  "ios_update_url": "https://apps.apple.com/app/idXXXXXXXXX"
}
```

### 實現步驟

1. **創建 VersionManager.swift**
```swift
import Foundation
import FirebaseRemoteConfig

class VersionManager: ObservableObject {
    static let shared = VersionManager()
    
    @Published var showForceUpdate = false
    @Published var showOptionalUpdate = false
    @Published var updateMessage = ""
    
    private let remoteConfig = RemoteConfig.remoteConfig()
    
    func checkVersion() async {
        // 1. 獲取當前版本
        let currentVersion = Bundle.main.appVersion
        
        // 2. 從 Remote Config 獲取配置
        await fetchRemoteConfig()
        
        let minimumVersion = remoteConfig["ios_minimum_version"].stringValue ?? "1.0.0"
        let latestVersion = remoteConfig["ios_latest_version"].stringValue ?? "1.0.0"
        let forceUpdate = remoteConfig["ios_force_update"].boolValue
        let message = remoteConfig["ios_update_message_zh"].stringValue ?? ""
        
        // 3. 版本比較
        if currentVersion.compare(minimumVersion) == .orderedAscending {
            // 當前版本 < 最低版本 → 強制更新
            await MainActor.run {
                self.updateMessage = message
                self.showForceUpdate = true
            }
        } else if currentVersion.compare(latestVersion) == .orderedAscending && !forceUpdate {
            // 當前版本 < 最新版本 → 可選更新
            await MainActor.run {
                self.updateMessage = message
                self.showOptionalUpdate = true
            }
        }
    }
    
    private func fetchRemoteConfig() async {
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600 // 1小時
        remoteConfig.configSettings = settings
        
        do {
            try await remoteConfig.fetch()
            try await remoteConfig.activate()
        } catch {
            print("❌ Remote Config fetch failed: \(error)")
        }
    }
}

extension Bundle {
    var appVersion: String {
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    var buildNumber: String {
        return infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
```

2. **創建強制更新視圖**
```swift
// ForceUpdateView.swift
struct ForceUpdateView: View {
    let message: String
    let updateURL: String
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("需要更新")
                .font(.title)
                .fontWeight(.bold)
            
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                if let url = URL(string: updateURL) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("立即更新")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
        .interactiveDismissDisabled(true) // 不能關閉
    }
}
```

3. **在 App 啟動時檢查**
```swift
// WorkoutRecordApp.swift
@main
struct WorkoutRecordApp: App {
    @StateObject private var versionManager = VersionManager.shared
    
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if versionManager.showForceUpdate {
                    ForceUpdateView(
                        message: versionManager.updateMessage,
                        updateURL: "https://apps.apple.com/app/idXXXX"
                    )
                } else {
                    // 正常應用流程
                    ContentView()
                }
            }
            .task {
                await versionManager.checkVersion()
            }
        }
    }
}
```

---

## 2️⃣ Firebase Authentication 用戶記錄

### 架構設計

```
Apple ID 登入成功
  ↓
獲取 Apple ID Credential
  ↓
轉換為 Firebase Auth Token
  ↓
Firebase Authentication
  ↓
創建/更新 Firestore 用戶文檔
  ↓
本地存儲 User ID
```

### Firestore 數據結構

```
firestore/
└── users/
    └── {uid}/
        ├── profile (document)
        │   ├── appleID: string
        │   ├── email: string (anonymized)
        │   ├── displayName: string
        │   ├── photoURL: string?
        │   ├── createdAt: timestamp
        │   ├── lastLoginAt: timestamp
        │   └── preferences: map
        │       ├── language: string
        │       ├── weightUnit: string
        │       └── theme: string
        ├── device (document)
        │   ├── platform: "iOS"
        │   ├── osVersion: string
        │   ├── appVersion: string
        │   ├── deviceModel: string
        │   └── lastSeenAt: timestamp
        └── subscription (document)
            ├── status: "free" | "premium"
            ├── tier: "basic" | "pro"
            ├── startDate: timestamp?
            ├── expiryDate: timestamp?
            └── autoRenew: boolean
```

### 實現步驟

1. **創建 FirebaseAuthService.swift**
```swift
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices

class FirebaseAuthService: ObservableObject {
    static let shared = FirebaseAuthService()
    
    @Published var currentUser: FirebaseAuth.User?
    @Published var isAuthenticated = false
    
    private let auth = Auth.auth()
    private let db = Firestore.firestore()
    
    init() {
        // 監聽認證狀態
        auth.addStateDidChangeListener { [weak self] _, user in
            self?.currentUser = user
            self?.isAuthenticated = user != nil
        }
    }
    
    // MARK: - Apple ID 登入
    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws {
        guard let idToken = credential.identityToken,
              let idTokenString = String(data: idToken, encoding: .utf8) else {
            throw AuthError.invalidCredential
        }
        
        // 1. 創建 Firebase Credential
        let firebaseCredential = OAuthProvider.credential(
            providerID: .apple,
            idToken: idTokenString,
            rawNonce: nil
        )
        
        // 2. 登入 Firebase
        let result = try await auth.signIn(with: firebaseCredential)
        
        // 3. 記錄到 Firestore
        try await saveUserProfile(
            uid: result.user.uid,
            appleID: credential.user,
            email: credential.email,
            name: credential.fullName
        )
        
        // 4. 記錄登入事件
        AnalyticsService.shared.logEvent("user_login", parameters: [
            "provider": "apple",
            "uid": result.user.uid
        ])
    }
    
    // MARK: - 保存用戶資料
    private func saveUserProfile(
        uid: String,
        appleID: String,
        email: String?,
        name: PersonNameComponents?
    ) async throws {
        let userRef = db.collection("users").document(uid)
        
        // 檢查是否為新用戶
        let snapshot = try await userRef.getDocument()
        let isNewUser = !snapshot.exists
        
        // 用戶資料
        var userData: [String: Any] = [
            "appleID": appleID,
            "lastLoginAt": FieldValue.serverTimestamp()
        ]
        
        if isNewUser {
            // 新用戶
            userData["createdAt"] = FieldValue.serverTimestamp()
            userData["email"] = email ?? ""
            userData["displayName"] = name?.formatted() ?? ""
            
            // 預設訂閱狀態
            let subscriptionData: [String: Any] = [
                "status": "free",
                "tier": "basic",
                "autoRenew": false
            ]
            try await userRef.collection("subscription").document("current").setData(subscriptionData)
            
            AnalyticsService.shared.logEvent("user_signup_completed", parameters: ["uid": uid])
        }
        
        // 更新或創建用戶資料
        try await userRef.setData(userData, merge: true)
        
        // 記錄設備信息
        try await saveDeviceInfo(uid: uid)
    }
    
    // MARK: - 記錄設備信息
    private func saveDeviceInfo(uid: String) async throws {
        let deviceData: [String: Any] = [
            "platform": "iOS",
            "osVersion": UIDevice.current.systemVersion,
            "appVersion": Bundle.main.appVersion,
            "deviceModel": UIDevice.current.model,
            "lastSeenAt": FieldValue.serverTimestamp()
        ]
        
        try await db.collection("users").document(uid)
            .collection("device").document("current")
            .setData(deviceData, merge: true)
    }
    
    // MARK: - 登出
    func signOut() throws {
        try auth.signOut()
        isAuthenticated = false
    }
}

enum AuthError: Error {
    case invalidCredential
    case userNotFound
}
```

2. **整合到 Apple ID 登入流程**
```swift
// AppleIDAuthService.swift
func handleSignInWithApple(result: Result<ASAuthorization, Error>) async {
    switch result {
    case .success(let authorization):
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            return
        }
        
        do {
            // 原有邏輯...
            
            // 新增：同步到 Firebase
            try await FirebaseAuthService.shared.signInWithApple(credential: credential)
            
        } catch {
            print("❌ Firebase 登入失敗: \(error)")
        }
        
    case .failure(let error):
        print("❌ Apple ID 登入失敗: \(error)")
    }
}
```

---

## 3️⃣ CoreData 遷移策略

### 版本管理

```swift
// 1. 在 Xcode 中創建新版本
// WorkoutRecord.xcdatamodeld
//   ├── WorkoutRecord.xcdatamodel (v1.0)
//   └── WorkoutRecord 2.xcdatamodel (v2.0) ← 新版本
```

### 輕量級遷移（Lightweight Migration）

```swift
// CoreDataStack.swift
description?.shouldMigrateStoreAutomatically = true // ✅ 已有
description?.shouldInferMappingModelAutomatically = true // ✅ 已有

// 添加版本驗證
description?.setValue("1.0.0" as NSObject, forPragmaNamed: "application_id")
```

### 遷移前備份

```swift
// CoreDataStack.swift
func migrateIfNeeded() -> Bool {
    guard needsMigration() else { return true }
    
    // 1. 備份當前數據庫
    if !backupDatabase() {
        print("⚠️ 備份失敗，取消遷移")
        return false
    }
    
    // 2. 執行遷移
    do {
        try performMigration()
        return true
    } catch {
        print("❌ 遷移失敗: \(error)")
        // 3. 恢復備份
        restoreBackup()
        return false
    }
}

private func backupDatabase() -> Bool {
    guard let storeURL = persistentStoreURL else { return false }
    
    let backupURL = storeURL.deletingLastPathComponent()
        .appendingPathComponent("backup_\(Date().timeIntervalSince1970).sqlite")
    
    do {
        try FileManager.default.copyItem(at: storeURL, to: backupURL)
        UserDefaults.standard.set(backupURL.path, forKey: "LastBackupPath")
        return true
    } catch {
        print("❌ 備份失敗: \(error)")
        return false
    }
}
```

---

## 4️⃣ 用戶行為分析事件追蹤

### 分析服務擴展

```swift
// AnalyticsService.swift
extension AnalyticsService {
    // MARK: - 用戶生命週期
    func logAppFirstOpen() {
        logEvent("app_first_open", parameters: nil)
    }
    
    func logOnboardingCompleted(steps: Int, duration: TimeInterval) {
        logEvent("onboarding_completed", parameters: [
            "steps_count": steps,
            "duration_seconds": duration
        ])
    }
    
    // MARK: - 訓練相關
    func logWorkoutStarted(templateUsed: Bool) {
        logEvent("workout_started", parameters: [
            "template_used": templateUsed
        ])
    }
    
    func logWorkoutCompleted(duration: Int, volume: Double, exercises: Int, sets: Int) {
        logEvent("workout_completed", parameters: [
            "duration_minutes": duration,
            "total_volume_kg": volume,
            "exercises_count": exercises,
            "sets_count": sets
        ])
    }
    
    func logPRachieved(exercise: String, weight: Double, reps: Int) {
        logEvent("pr_achieved", parameters: [
            "exercise_name": exercise,
            "weight_kg": weight,
            "reps": reps
        ])
    }
    
    // MARK: - 設定變更
    func logWeightUnitChanged(from: String, to: String) {
        logEvent("weight_unit_changed", parameters: [
            "from_unit": from,
            "to_unit": to
        ])
    }
    
    func logThemeChanged(theme: String) {
        logEvent("theme_changed", parameters: [
            "theme": theme
        ])
    }
}
```

### 在關鍵位置添加追蹤

```swift
// WorkoutViewModel.swift
func completeWorkout() {
    stopTimer()
    saveWorkout { [weak self] workout in
        guard let self = self else { return }
        
        // 記錄分析事件
        AnalyticsService.shared.logWorkoutCompleted(
            duration: workout.duration ?? 0,
            volume: workout.totalVolume,
            exercises: workout.totalExercises,
            sets: workout.totalSets
        )
        
        // ... 其他邏輯
    }
}
```

---

## 5️⃣ 生產環境配置

### 環境變數管理

```swift
// Config.xcconfig (Production)
API_BASE_URL = https:/$()/api.workout-record.com
FIREBASE_API_KEY = your-production-api-key
FIREBASE_PROJECT_ID = workout-record-prod

// Config.xcconfig (Development)
API_BASE_URL = http:/$()/localhost:8080
FIREBASE_API_KEY = your-dev-api-key
FIREBASE_PROJECT_ID = workout-record-dev
```

### APIConfig 更新

```swift
// APIConfig.swift
struct APIConfig {
    static var baseURL: String {
        #if DEBUG
        return ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "http://localhost:8080"
        #else
        return ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.workout-record.com"
        #endif
    }
}
```

---

## 📋 實現優先級與時間估算

### 🔴 P0 - 上線前必須（2-3 天）
1. **版本管理系統** - 4小時
2. **Firebase Auth 整合** - 6小時
3. **分析事件追蹤** - 4小時
4. **生產環境配置** - 2小時

### 🟡 P1 - 上線後 1 週內（1-2 天）
5. **CoreData 遷移強化** - 6小時
6. **數據備份機制** - 4小時
7. **錯誤監控** - 2小時

### 🟢 P2 - 未來版本
8. **雲端同步** - 2 週
9. **訂閱功能** - 1 週
10. **Apple Watch** - 3 週

---

**文檔版本：** 1.0
**最後更新：** 2025-10-29
**作者：** Mike

