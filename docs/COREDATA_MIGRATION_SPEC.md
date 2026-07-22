# CoreData → Flutter/Drift 資料無縫匯入規格

> 目的：舊版 iOS App（SwiftUI + CoreData）將被同 bundle ID（`com.mikelin.workitout`）的 Flutter 版（Drift/SQLite）覆蓋安裝。使用者更新後，沙盒裡的舊 CoreData SQLite 檔仍在，Flutter 版首次啟動時要讀取它，把全部資料匯入 Drift。**硬性要求：不得遺失任何訓練歷史。**
>
> 本文件只做規格設計，不含任何實作程式碼；供另一位工人依此文件直接實作。

---

## 0. 背景重點（先讀）

- 這是一個**單一使用者**的本機 App：Apple ID 登入（`AppleIDAuthService`）只是 UI 層的登入閘門，並**沒有**對應到 CoreData 裡某一筆 `UserEntity`。實際資料的「使用者」身分，是 `DataMigrationService.createDefaultUser()` 在第一次啟動時建立的唯一一筆 `UserEntity`，其 `id`（UUID）被存進 `UserDefaults` 的 `CurrentUserId`。也就是說：**匯入時不需要處理多帳號分流，但仍要把這筆 `UserEntity` 本身，以及所有以裸 UUID 屬性（`userId`）掛在它底下的資料，原封不動地搬過去。**
- App 沒有啟用 CloudKit（entitlements 裡沒有 `icloud-container-identifiers` / `icloud-services`，`CoreDataStack.swift` 裡的 `NSPersistentCloudKitContainerOptions` 也被註解掉），純本機 CoreData，不用擔心雲端同步造成的資料競態。
- **重要風險提示（不是這次移轉要修，但要讓 Mike 知道）**：`WorkoutRecordApp.swift` 裡有一段用 `UserDefaults` 的 `CoreDataModelVersion`（目前寫死字串 `"2.3"`）比對版本號的邏輯，只要版本號不符，就會**主動刪除** Application Support / Documents / Library 三個目錄下的 `WorkoutRecord.sqlite*` 檔案來重建空庫。這代表：如果使用者的裝置曾經跨過這段版本號判斷的邊界（過去某次 App 更新時改過這個字串，註解裡就寫著「修復分類 UUID 為固定值」），他們的舊資料可能早就已經被這段邏輯清空過。**現在裝置上留著的 CoreData 內容，不一定是完整歷史，而是最近一次版本號匹配以來累積的資料。** 這次 Flutter 匯入只能讀取「現存」的內容，無法找回已經被這段舊邏輯刪除的資料。

---

## 1. 舊資料庫位置

### 1.1 CoreData 端設定

`ios/WorkoutRecord/WorkoutRecord/Sources/Services/CoreDataStack.swift`：

```swift
let container = NSPersistentContainer(name: "WorkoutRecord")
// ...沒有自訂 description.url...
description?.shouldMigrateStoreAutomatically = true
description?.shouldInferMappingModelAutomatically = true
```

沒有覆寫 `persistentStoreDescriptions.first?.url`，所以走 `NSPersistentContainer` 的預設規則：

- Store 檔名 = `<container name>.sqlite` = **`WorkoutRecord.sqlite`**
- 預設目錄（iOS）= `defaultDirectoryURL()`，也就是 App 沙盒的 **`Library/Application Support`**（iOS 上不像 macOS 會再加 bundle-id 子資料夾，直接放在 Application Support 根目錄下）。

這點也被 App 自己的防呆程式碼間接證實：`WorkoutRecordApp.swift` 裡 `checkAndResetCoreDataIfNeededSync()` 會分別檢查 `.applicationSupportDirectory`、`.documentDirectory`、`.libraryDirectory` 三處是否有 `WorkoutRecord.sqlite`／`-shm`／`-wal`，這是「不確定所以三處都刪一遍」的防呆寫法，但也確認了正式位置就是 Application Support，其餘兩處正常情況下不會有檔案。

需要一起處理的檔案（WAL 模式，只複製主檔會漏資料）：

```
Library/Application Support/WorkoutRecord.sqlite
Library/Application Support/WorkoutRecord.sqlite-wal
Library/Application Support/WorkoutRecord.sqlite-shm
```

### 1.2 Flutter 端對應路徑

`path_provider` 的 `getApplicationSupportDirectory()` 在 iOS 上底層就是 `NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)`，跟 CoreData 預設用的目錄是**同一個**。由於新舊 App 是同一個 bundle ID（`com.mikelin.workitout`）覆蓋安裝，沙盒容器本身沒有換，也沒有用到 App Group（`WorkoutRecord.entitlements` 裡沒有 app group 設定），所以 Flutter 端不需要任何特殊權限，直接用：

```dart
final supportDir = await getApplicationSupportDirectory();
final oldDbFile = File('${supportDir.path}/WorkoutRecord.sqlite');
final oldWalFile = File('${supportDir.path}/WorkoutRecord.sqlite-wal');
final oldShmFile = File('${supportDir.path}/WorkoutRecord.sqlite-shm');
```

判斷「有沒有舊資料需要匯入」= `oldDbFile.existsSync()`。

Android 端：這台裝置上根本不會有這個檔案（這是 iOS-only 的舊 App 換代），同一套「檔案是否存在」判斷會自然回傳 false 並跳過，**不需要寫 `Platform.isIOS` 特判**。

---

## 2. Schema 完整對照表

### 2.1 找出真正被編譯進 App 的 model（重要地雷）

專案裡有**兩份** `.xcdatamodeld`，且內容不一致：

| 路徑 | 狀態 |
|---|---|
| `ios/WorkoutRecord/WorkoutRecord/Sources/WorkoutRecord.xcdatamodeld` | ✅ 真正被建置採用 |
| `ios/WorkoutRecord/WorkoutRecord.xcdatamodeld`（專案根目錄那份） | ❌ 孤兒舊檔，不會被編譯進 App |

判斷依據：`WorkoutRecord.xcodeproj/project.pbxproj` 用的是 Xcode 16 的 `PBXFileSystemSynchronizedRootGroup` 機制（檔案不用逐一在 pbxproj 裡列出，整個資料夾自動同步進專案），其 root group 的 `path = "WorkoutRecord"`（相對於 `.xcodeproj` 所在目錄 `ios/WorkoutRecord/`），對應到 `ios/WorkoutRecord/WorkoutRecord/` 這個資料夾。`Sources/WorkoutRecord.xcdatamodeld` 在這個資料夾底下，會被自動納入建置；上一層那份不在裡面，不會被編譯。

兩者差異（若誤用孤兒版本，匯入程式會漏欄位/漏實體）：

- `WorkoutExerciseEntity` 少了 `exerciseName`、`isCompleted`、`isCustomExercise` 三個屬性。
- 完全沒有 `PowerLiftRecordEntity` 這個實體。
- `PersonalRecordEntity` / `UserGoalEntity` 的 `codeGenerationType` 是 `category` 而非 `class`（不影響資料本身，只影響 Swift 端程式碼產生方式）。

**下面的對照表一律以 `Sources/WorkoutRecord.xcdatamodeld`（正式版）為準。**

### 2.2 CoreData → SQLite 命名慣例（給實作參考，務必用真實檔案驗證）

CoreData 用 SQLite 做底層儲存時的慣例：

- 每個 entity → 資料表 `Z<ENTITY NAME 全大寫>`，例如 `UserEntity` → `ZUSERENTITY`。
- 每個 attribute → 欄位 `Z<ATTRIBUTE NAME 全大寫>`，例如 `createdAt` → `ZCREATEDAT`。
- 每個 to-one relationship → 欄位 `Z<RELATIONSHIP NAME 全大寫>`，存的是對方那筆資料在 `Z_PK` 裡的整數值（外鍵）。
- 一對多（本專案的 to-many 都有對應的 to-one inverse，不是多對多）不會另開 join table，外鍵直接放在「多」的那一側資料表上（也就是子實體自己 to-one 那個 relationship 的欄位）。
- 每張表固定有 `Z_PK`（內部整數主鍵，跟 CoreData 的 `id` UUID 屬性是兩件事）、`Z_ENT`、`Z_OPT`。另有一張 `Z_PRIMARYKEY` 表記錄每個實體的 `Z_ENT` 編號對應。
- **Ordered 的 to-many relationship**（本專案裡 `WorkoutEntity.exercises`、`WorkoutExerciseEntity.sets`、`TemplateEntity.exercises` 都是 `ordered="YES"`）在子表上還會有額外的排序欄位，其確切命名（例如常見的 `Z_FOK_*`／隱含排序欄位）**是 Xcode 編譯期產生的實作細節，不同 Xcode 版本可能不同，不能只靠本文件的推測**。

> ⚠️ **實作前必做**：用第 5 節「驗收測試」準備的真實 fixture（從模擬器抓出的 `.sqlite`），跑一次 `sqlite3 WorkoutRecord.sqlite ".schema"` 把實際欄位名稱、外鍵欄位、排序欄位全部dump出來，對照下面表格逐一核對，再動手寫轉換程式。下面表格的「屬性層級內容」（欄名、型別、optional、預設值）100% 來自 `.xcdatamodeld` 原始碼可直接信任；但「Z 前綴的實際 SQLite 欄名」只是慣例推測，務必用 dump 結果覆核。

### 2.3 型別轉換規則

| CoreData 型別 | SQLite 實際儲存 | 轉換到 Drift 需要做的事 |
|---|---|---|
| `UUID`（`usesScalarValueType="NO"`） | 16-byte BLOB | 轉成標準 `8-4-4-4-12` 格式的 UUID 字串（Drift 用 TEXT 存 UUID） |
| `Date`（`usesScalarValueType="NO"`） | REAL（Core Data 參考日期 2001-01-01 起的秒數） | **Unix 秒 = CoreData 值 + 978307200**；若 Drift 欄位存 unix millis，再 `* 1000` |
| `Boolean` | INTEGER（0/1） | 直接對應，Drift bool 同樣存 0/1 |
| `Integer 32` | INTEGER | 直接對應 |
| `Double` | REAL | 直接對應，注意 `weight`/`volume` 等數值不要在轉換過程中損失精度（避免先轉 String 再轉回） |
| `String` | TEXT | 直接對應 |
| optional 數值屬性（如 `restSeconds`、`rpe`）未賦值時 | CoreData 物件層面常會 fallback 用 `defaultValueString`，不一定是 SQL NULL | 轉換時仍建議用 `COALESCE`／null-safe 寫法保險，不要假設一定有值也不要假設一定是 NULL |

### 2.4 各 Entity 屬性表（共 11 個 entity）

#### UserEntity（5 屬性 + 4 關聯）

| 屬性 | CoreData 型別 | Optional | Default |
|---|---|---|---|
| id | UUID | 否 | — |
| name | String | 是 | — |
| email | String | 是 | — |
| createdAt | Date | 否 | — |
| updatedAt | Date | 否 | — |

關聯：`bodyWeights`/`exercises`/`templates`/`workouts`（皆為 to-many，cascade，inverse 為子表的 `user` to-one）。

#### WorkoutEntity（13 屬性 + 2 關聯）

| 屬性 | 型別 | Optional | Default |
|---|---|---|---|
| id | UUID | 否 | — |
| userId | UUID | 否 | — |
| startedAt | Date | 否 | — |
| endedAt | Date | 是 | — |
| duration | Integer 32 | 是 | 0 |
| totalVolume | Double | 否 | 0.0 |
| totalSets | Integer 32 | 否 | 0 |
| totalExercises | Integer 32 | 否 | 0 |
| note | String | 是 | — |
| templateId | UUID | 是 | — |
| isSynced | Boolean | 否 | NO |
| createdAt | Date | 否 | — |
| updatedAt | Date | 否 | — |

關聯：`exercises`（to-many, **ordered**, cascade → `WorkoutExerciseEntity.workout`）、`user`（to-one, nullify → `UserEntity.workouts`）。

#### WorkoutExerciseEntity（12 屬性 + 3 關聯）※ 比孤兒 model 多 3 個屬性

| 屬性 | 型別 | Optional | Default | 備註 |
|---|---|---|---|---|
| id | UUID | 否 | — | |
| workoutId | UUID | 否 | — | |
| exerciseId | UUID | 否 | — | |
| exerciseName | String | 是 | — | **新增，孤兒 model 沒有** |
| orderIndex | Integer 32 | 否 | 0 | |
| totalVolume | Double | 否 | 0.0 | |
| totalSets | Integer 32 | 否 | 0 | |
| isCompleted | Boolean | 否 | NO | **新增** |
| isCustomExercise | Boolean | 否 | NO | **新增** |
| note | String | 是 | — | |
| createdAt | Date | 否 | — | |
| updatedAt | Date | 否 | — | |

關聯：`exercise`（to-one, nullify → `ExerciseEntity.workoutExercises`）、`sets`（to-many, **ordered**, cascade → `WorkoutSetEntity.workoutExercise`）、`workout`（to-one, nullify → `WorkoutEntity.exercises`）。

#### WorkoutSetEntity（11 屬性 + 1 關聯）

| 屬性 | 型別 | Optional | Default |
|---|---|---|---|
| id | UUID | 否 | — |
| workoutExerciseId | UUID | 否 | — |
| setNumber | Integer 32 | 否 | 0 |
| weight | Double | 否 | 0.0 |
| reps | Integer 32 | 否 | 0 |
| volume | Double | 否 | 0.0 |
| rpe | Double | 是 | 0.0 |
| restSeconds | Integer 32 | 是 | 0 |
| isWarmup | Boolean | 否 | NO |
| note | String | 是 | — |
| createdAt | Date | 否 | — |
| updatedAt | Date | 否 | — |

（表格含 12 行是因為 `createdAt`/`updatedAt` 分開列；實際屬性數以 xcdatamodeld 為準，共 11 個資料屬性。）

關聯：`workoutExercise`（to-one, nullify → `WorkoutExerciseEntity.sets`）。

#### BodyWeightEntity（7 屬性 + 1 關聯）

| 屬性 | 型別 | Optional | Default |
|---|---|---|---|
| id | UUID | 否 | — |
| userId | UUID | 否 | — |
| weight | Double | 否 | 0.0 |
| measuredAt | Date | 否 | — |
| note | String | 是 | — |
| isSynced | Boolean | 否 | NO |
| createdAt | Date | 否 | — |
| updatedAt | Date | 否 | — |

關聯：`user`（to-one, nullify → `UserEntity.bodyWeights`）。

#### ExerciseEntity（14 屬性 + 2 關聯）

| 屬性 | 型別 | Optional | Default | 備註 |
|---|---|---|---|---|
| id | UUID | 否 | — | |
| name | String | 否 | — | |
| nameEn | String | 是 | — | |
| categoryId | UUID | 否 | — | **沒有對應的 CoreData 分類實體**（見附錄） |
| type | String | 否 | — | |
| movementPattern | String | 是 | — | |
| primaryMuscleGroup | String | 是 | — | |
| descriptionText | String | 是 | — | |
| videoURL | String | 是 | — | |
| imageURL | String | 是 | — | |
| isSystem | Boolean | 否 | NO | |
| isActive | Boolean | 否 | YES | |
| userId | UUID | 是 | — | 自訂動作的建立者；系統動作為 nil |
| createdAt | Date | 否 | — | |
| updatedAt | Date | 否 | — | |

關聯：`user`（to-one optional, nullify → `UserEntity.exercises`）、`workoutExercises`（to-many, nullify → `WorkoutExerciseEntity.exercise`）。

#### TemplateEntity（6 屬性 + 2 關聯）

| 屬性 | 型別 | Optional | Default |
|---|---|---|---|
| id | UUID | 否 | — |
| userId | UUID | 否 | — |
| name | String | 否 | — |
| descriptionText | String | 是 | — |
| isSystem | Boolean | 否 | NO |
| createdAt | Date | 否 | — |
| updatedAt | Date | 否 | — |

關聯：`exercises`（to-many, **ordered**, cascade → `TemplateExerciseEntity.template`）、`user`（to-one, nullify → `UserEntity.templates`）。

#### TemplateExerciseEntity（6 屬性 + 1 關聯）

| 屬性 | 型別 | Optional | Default |
|---|---|---|---|
| id | UUID | 否 | — |
| templateId | UUID | 否 | — |
| exerciseId | UUID | 否 | — |
| orderIndex | Integer 32 | 否 | 0 |
| suggestedSets | Integer 32 | 是 | 0 |
| suggestedReps | Integer 32 | 是 | 0 |

關聯：`template`（to-one, nullify → `TemplateEntity.exercises`）。

#### PersonalRecordEntity（10 屬性，無關聯）

| 屬性 | 型別 | Optional | Default | 備註 |
|---|---|---|---|---|
| id | UUID | 否 | — | |
| userId | UUID | 否 | — | |
| exerciseId | UUID | 否 | — | |
| oneRepMax | Double | 否 | 0.0 | |
| weight | Double | 否 | 0.0 | |
| reps | Integer 32 | 否 | 0 | |
| achievedAt | Date | 否 | — | |
| workoutId | UUID | 是 | — | |
| createdAt | Date | 否 | — | |
| updatedAt | Date | 否 | — | |

⚠️ 沒有 `record_type` 這種欄位（docs 裡的設計有，CoreData 實際沒有），只記錄 1RM 這一種指標，見附錄。

#### UserGoalEntity（13 屬性，無關聯）

| 屬性 | 型別 | Optional | Default |
|---|---|---|---|
| id | UUID | 否 | — |
| userId | UUID | 否 | — |
| targetWeight | Double | 是 | 0.0 |
| weeklyWorkoutGoal | Integer 32 | 否 | 0 |
| chestVolumeGoal | Double | 是 | 0.0 |
| backVolumeGoal | Double | 是 | 0.0 |
| legsVolumeGoal | Double | 是 | 0.0 |
| shouldersVolumeGoal | Double | 是 | 0.0 |
| armsVolumeGoal | Double | 是 | 0.0 |
| coreVolumeGoal | Double | 是 | 0.0 |
| restDayReminder | Boolean | 否 | NO |
| createdAt | Date | 否 | — |
| updatedAt | Date | 否 | — |

⚠️ `docs/DATABASE_SCHEMA.md` 完全沒有這個實體，見附錄。

#### PowerLiftRecordEntity（9 屬性，無關聯）※ 孤兒 model 和 docs 都沒有

| 屬性 | 型別 | Optional | Default |
|---|---|---|---|
| id | UUID | 否 | — |
| userId | UUID | 否 | — |
| lift | String | 否 | — |
| oneRepMax | Double | 否 | 0.0 |
| weight | Double | 否 | 0.0 |
| reps | Integer 32 | 否 | 1 |
| achievedAt | Date | 否 | — |
| note | String | 是 | — |
| createdAt | Date | 否 | — |
| updatedAt | Date | 否 | — |

**合計：11 個 entity，共約 106 個資料屬性（不含關聯欄位）。**

### 2.5 建議的 Drift 對應原則

（實際型別/欄位名以 `app/lib` 內既有的 Drift table 定義為準，這裡只給轉換設計上的建議）

- 每個 CoreData entity → 一張 Drift table，命名可用 snake_case（如 `workout_exercises`）。
- CoreData 的 `id`（UUID）→ Drift 用 `TEXT` 存 UUID 字串，當作主鍵，不要用 CoreData 內部的 `Z_PK` 整數（那個只在舊 SQLite 內部有意義，匯入後不需要保留）。
- 所有 `xxxId` 外鍵屬性（`userId`/`workoutId`/`exerciseId`…）→ 一樣轉成 UUID 字串存進對應的外鍵欄位。
- Date → 依 Flutter 端 Drift schema 決定的儲存慣例（unix millis 或 ISO8601 字串）統一轉換，換算基準一律是「先 +978307200 轉成 unix 秒」。
- Ordered 的 to-many 關聯（`WorkoutEntity.exercises`、`WorkoutExerciseEntity.sets`、`TemplateEntity.exercises`）匯入後的順序，建議直接用實體自己既有的 `orderIndex`（`WorkoutExerciseEntity.orderIndex`、`TemplateExerciseEntity.orderIndex`）欄位排序即可，**不需要**額外去解析 CoreData 內部的排序欄位——這些業務欄位本來就存在，比依賴 CoreData 實作細節可靠。

---

## 3. UserDefaults / 使用者偏好遷移

### 3.1 全部 key 清單（`grep -rn "UserDefaults" ios/ --include="*.swift"` 找到的）

| Key | 型別 | 用途 | 寫入位置 |
|---|---|---|---|
| `AppleIDUserID` | String | Apple ID 登入用戶識別碼 | `AppleIDAuthService.swift` |
| `AppleIDUserName` | String | Apple ID 姓名 | 同上 |
| `AppleIDUserEmail` | String | Apple ID email | 同上 |
| `CloudKitUserID` | String | CloudKit 帳號 ID（目前 CloudKit 未真正啟用，可忽略） | `CloudKitAuthService.swift` |
| `CloudKitUserName` | String | 同上 | 同上 |
| `CloudKitUserEmail` | String | 同上 | 同上 |
| `CurrentUserId` | String（UUID 字串） | **對應到 CoreData `UserEntity.id`**，全 App 用它決定「目前使用者」 | `DataMigrationService.swift` / `ComprehensiveAnalyticsService.swift` / `LocalAnalyticsService.swift` |
| `CoreDataMigrationCompleted` | Bool | 舊 App 內部「Mock 資料 → CoreData」的遷移旗標（跟這次 CoreData→Drift 無關，是舊 App 自己的歷史遷移） | `DataMigrationService.swift` |
| `CoreDataModelVersion` | String | 舊 App 拿來判斷要不要清空重建資料庫的版本字串（目前 `"2.3"`） | `WorkoutRecordApp.swift` |
| `DefaultDataInitialized` | Bool | 是否已建立預設使用者/系統動作庫/範例模板 | 多處 |
| `ForceResetCoreData` | Bool | 手動強制重置資料庫的開發用旗標 | `CoreDataStack.swift` |
| `HasAgreedToAnalytics` | Bool | 隱私同意（分析） | `PrivacyConsentService.swift` |
| `HasAgreedToPrivacy` | Bool | 隱私同意（隱私權） | 同上 |
| `PrivacyConsentDate` | Date | 同意時間 | 同上 |
| `PrivacyPolicyAccepted` | Bool | 另一個獨立的隱私政策同意旗標（`PrivacyPolicyView.swift`，跟上面兩個是不同的旗標，疑似重複設計） | `PrivacyPolicyView.swift` |
| `PrivacyPolicyAcceptedDate` | Date | 同上 | 同上 |
| `isDarkMode` | Bool | 深色模式 | `ThemeManager.swift` |
| `accentColor` | Data（`NSKeyedArchiver` 編碼的 `UIColor`/`Color`） | 主題色 | `ThemeManager.swift` |
| `reminderTime` | Date | 訓練提醒時間 | `NotificationSettingsView.swift` |
| `lastViewedAchievementsDate` | Date | 最後查看成就頁時間 | `AchievementsViewModel.swift` |
| `UnlockedAchievements` | Data（JSON/Codable 編碼） | 已解鎖成就清單 | 同上 |
| `LastDataCleanup` | Date | 上次資料保留清理時間 | `DataRetentionService.swift` |
| `GlobalSettings` | Data（JSON 編碼的 `SettingsData`） | **目前實際生效**的使用者偏好：`weightUnit`/`theme`/`oneRMFormula`/`defaultRestTime`/`showVolumeInStats`/`enableHapticFeedback`/`autoSaveWorkout` | `GlobalSettingsManager.swift`（注意：這個 key 是拼在程式碼變數 `settingsKey` 裡，直接 `grep "GlobalSettings"` 才找得到，用 `grep "forKey:"` 搜不到） |
| `weightUnit` / `theme` / `oneRMFormula` / `defaultRestTime` / `enableAutoRestTimer` / `enableHapticFeedback` | 各自型別 | **已標記 `@available(*, deprecated)`** 的 `AppSettings` 類別用的 `@AppStorage` key，跟 `GlobalSettings` 是兩套並存的舊設計 | `AppSettings.swift` |
| `userName` / `userEmail` / `userGender` / `userAge` / `userHeight` / `userCurrentWeight` / `userTargetWeight` / `weeklyWorkoutGoal` | 各自型別 | `UserProfile` 類別（非 deprecated，`AppleIDAuthService.updateUserProfile()` 登入成功後仍會寫入 `userName`/`userEmail`） | `AppSettings.swift`（`UserProfile` class）|
| `ComprehensiveAnalyticsData` / `LocalAnalyticsData` / `analytics_events` / `analytics_user_<key>` | 各自型別 | 分析用資料，非使用者訓練歷史，**建議不遷移** | 各 Analytics Service |

### 3.2 哪些需要遷移

**需要遷移（會影響使用者體感/資料一致性）：**
- `CurrentUserId` → 對應到匯入後 Drift 裡 `UserEntity` 那筆的 id，必須確保兩邊一致（Flutter 端「目前使用者」的判斷邏輯要沿用同一顆 UUID，不要重新生成）。
- `GlobalSettings`（JSON blob）→ 這是目前實際生效的偏好設定，優先遷移。
- `AppSettings`/`UserProfile` 裡的個別 key（`weightUnit`/`theme`/`oneRMFormula`/`userName`/`userEmail`/`userHeight`/`userTargetWeight`/`weeklyWorkoutGoal` 等）→ 雖然 `AppSettings` 類別本身被標記 deprecated，但 `UserProfile`（`userName`/`userEmail`）仍在被 `AppleIDAuthService` 主動寫入，且沒有代碼證實 `GlobalSettings` 一定涵蓋所有欄位（例如 `userHeight`/`userTargetWeight` 只在 `UserProfile` 裡有，`GlobalSettings` 沒有），**建議兩邊都讀，`GlobalSettings` 優先，缺的欄位用 `AppSettings`/`UserProfile` 的舊 key 補**。
- `AppleIDUserID`/`AppleIDUserName`/`AppleIDUserEmail` → 若 Flutter 版要沿用同一套「已登入」判斷，需要遷移；若 Flutter 版打算重新走一次 Apple 登入流程，則只需確認「已登入」狀態本身不用特別搬（使用者重新登入一次即可，Apple 的 `userID` 不會變）。**這點建議跟 Mike 確認 Flutter 版的登入流程設計後再決定**，不在本文件範圍內下定論。
- `isDarkMode` / `accentColor` / `reminderTime` / `UnlockedAchievements` / `lastViewedAchievementsDate` → 使用者體感相關，建議遷移。

**不建議遷移：**
- `CoreDataMigrationCompleted` / `CoreDataModelVersion` / `DefaultDataInitialized` / `ForceResetCoreData` → 都是舊 App 內部狀態機用的旗標，跟舊 SQLite 檔案本身的結構綁定，Flutter 版有自己全新的初始化邏輯，這些 key 沒有意義。
- `ComprehensiveAnalyticsData` / `LocalAnalyticsData` / `analytics_events` / `analytics_user_*` → 分析數據，非使用者資產。
- `CloudKitUserID`/`CloudKitUserName`/`CloudKitUserEmail` → CloudKit 目前未真正啟用（entitlements 沒開），可忽略。
- `PrivacyPolicyAccepted`/`PrivacyPolicyAcceptedDate` vs `HasAgreedToPrivacy`/`PrivacyConsentDate`：這是舊 App 裡兩套並存、疑似重複的隱私同意記錄（`PrivacyPolicyView.swift` 和 `PrivacyConsentService.swift` 各自獨立寫入）。**建議 Flutter 版重新設計一套隱私同意流程並要求使用者重新確認一次**，不需要糾結怎麼把兩套舊旗標合併遷移過去——重新同意一次的使用者成本很低，遠低於把兩套邏輯不一致的舊資料搬過去可能出的錯。

### 3.3 Flutter 怎麼讀舊的 NSUserDefaults（結論）

`shared_preferences` 套件在 iOS 上底層雖然也是用 `NSUserDefaults(suiteName:)`，但**新舊兩個 App 是各自獨立的二進位檔**，`shared_preferences` 初次執行時並不會自動去讀取舊 App 遺留在 `NSUserDefaults.standardUserDefaults` 裡、但 `shared_preferences` 自己從未寫過的 key —— 這是誤解，實際上 iOS 的 `NSUserDefaults.standard` **就是整個 App 沙盒共用的同一份 plist**（位於 `Library/Preferences/com.mikelin.workitout.plist`），不區分是哪個套件寫入的。只要 Flutter 版跟舊 App 用**同一個 bundle ID**覆蓋安裝，`Library/Preferences/com.mikelin.workitout.plist` 這個檔案本身也會原封不動留在沙盒裡。

評估兩種作法：

| 作法 | 說明 | 評估 |
|---|---|---|
| A. Platform Channel 呼叫原生 `UserDefaults.standard` | 寫一小段 Swift 原生 code（`MethodChannel`），用 `UserDefaults.standard.string(forKey:)` 等 API 直接讀取，回傳給 Dart | ✅ **建議採用**。這是 Apple 官方 API，不用管檔案格式版本、不用自己解析 plist 二進位格式，各種型別（Bool/String/Date/Data）都有現成 API，且跟本文件其他部分一樣是「讀取舊資料」的單次性操作，寫一個小的 iOS-only Swift 檔案（例如 `ios/Runner/CoreDataMigrationChannel.swift`）搭配 Flutter 端 `MethodChannel('coredata_migration')` 即可 |
| B. Flutter 端直接讀 `Library/Preferences/com.mikelin.workitout.plist` | 用 path_provider 找到 Preferences 目錄，直接解析 plist 檔案（binary plist 格式） | ❌ 不建議。plist 檔名雖然理論上是 bundle-id.plist，但 `NSUserDefaults` 什麼時候把記憶體內容 flush 到磁碟上的 plist 是系統控制的（不保證即時），若舊 App 結束前沒有觸發同步，磁碟上的 plist 內容可能是舊的；且 Dart 生態沒有成熟穩定的 binary plist parser，得自己處理 `Date`/`Data`(NSKeyedArchiver 編碼，如 `accentColor`)等特殊型別的二進位格式，複雜度和風險都比方案 A 高 |

**結論：採用方案 A（Platform Channel 讀原生 `UserDefaults.standard`）**。只在 iOS 平台呼叫（Android 沒有這個 channel/舊資料，直接跳過）；讀到的值在同一次匯入流程中，跟第 4 節的 CoreData 匯入一起寫進 Flutter 這邊對應的儲存位置（`GlobalSettings` 這種 JSON blob，Platform Channel 讀回來後在 Dart 端自己 `jsonDecode`，不用假手原生端解析）。

---

## 4. 匯入流程設計

### 4.1 首啟偵測順序

```
App 啟動
  → 檢查 Flutter 自己的匯入完成旗標（SharedPreferences key，例如 "coredata_import_done_v1"，
     刻意取一個新名字，避免跟舊 App 遺留在同一份 plist 裡的任何 key 語意衝突/誤判）
  → 若已標記完成：略過，走正常 Drift 初始化
  → 若未標記：
      → 用 path_provider 取得 Application Support 目錄，檢查 WorkoutRecord.sqlite 是否存在
      → 不存在（全新安裝 / Android / 或舊 App 從未初始化過）：
          → 直接標記匯入完成並跳過，不視為錯誤
      → 存在：進入 4.2 匯入流程
```

Android 完全不需要 `Platform.isIOS` 特判——檔案天然不存在，同一套邏輯自動短路跳過。

### 4.2 唯讀讀取舊庫

1. 把 `WorkoutRecord.sqlite` / `-wal` / `-shm`（若存在）**複製**一份到 App 自己的暫存目錄（`getTemporaryDirectory()` 或 `getApplicationCacheDirectory()`），不要直接在原始檔案上操作。
   - 原因：WAL 模式下唯讀開啟仍需要能建立/更新 `-shm` 共享記憶體鎖檔，若對原始容器目錄的存取行為跟預期不同（例如同時有其他行程持有鎖），直接在原地操作有不必要的風險；複製一份到自己完全掌控的暫存目錄，可以安全地做唯讀 attach，不會動到原始檔案，也不會被舊資料庫殘留的鎖狀態卡住。
2. 用 `drift`/`sqlite3` 套件（`sqlite3` 是 drift 依賴的原生 binding，`pubspec.yaml` 已有 `sqlite3_flutter_libs`）以唯讀模式開啟複製後的檔案：`sqlite3.open(copiedPath, mode: OpenMode.readOnly)`。
3. 或者用 `ATTACH DATABASE 'copied_path' AS old_db;` 掛載到目前的 Drift connection 上，直接用 `SELECT ... FROM old_db.ZWORKOUTENTITY` 這種語法跨庫查詢，一邊讀一邊寫進新 schema，可以減少一次「先讀進記憶體物件、再寫入」的中間層。兩種寫法都可以，選一個實作起來簡單的即可。

### 4.3 逐表轉換順序

依照父子關係（先父後子），建議轉換順序：

1. `ZUSERENTITY` → `users`
2. `ZEXERCISEENTITY` → `exercises`
3. `ZTEMPLATEENTITY` → `templates`
4. `ZTEMPLATEEXERCISEENTITY` → `template_exercises`
5. `ZWORKOUTENTITY` → `workouts`
6. `ZWORKOUTEXERCISEENTITY` → `workout_exercises`
7. `ZWORKOUTSETENTITY` → `workout_sets`
8. `ZBODYWEIGHTENTITY` → `body_weights`
9. `ZPERSONALRECORDENTITY` → `personal_records`
10. `ZUSERGOALENTITY` → `user_goals`
11. `ZPOWERLIFTRECORDENTITY` → `power_lift_records`

每張表轉換時依第 2.3 節規則做型別轉換（UUID blob→字串、Date +978307200、Bool 0/1 直通）。

### 4.4 交易包裹

全部 11 張表的轉換寫入，包在**同一個** Drift transaction（`db.transaction(() async { ... })`）裡：任何一步失敗，整個 rollback，不會留下部分匯入的髒資料。個人健身紀錄 App 的資料量級（通常幾千筆 `workout_sets` 等級）可以一次讀進記憶體轉換再寫入，不需要分批，除非之後實測發現效能問題再優化成 batch insert。

### 4.5 成功後標記完成

- 寫入 `coredata_import_done_v1 = true`。
- 同時記錄一份匯入統計（各表筆數）到本地，例如 `coredata_import_summary`（JSON 字串），方便日後 debug 或跟使用者核對「東西是不是都搬過來了」。
- **舊 CoreData 檔案（`.sqlite`/`-wal`/`-shm`）保留在原地，不刪除**，作為保險（萬一之後發現匯入邏輯有 bug，需要重跑或人工排查）。這次範圍不處理「之後某個穩定版本再清掉舊檔」的問題。
- 複製到暫存目錄的副本，匯入結束後可以刪除（避免占用額外空間）。

### 4.6 失敗時的重試與回報

- 任一步驟丟例外（檔案不存在、attach 失敗、schema 跟預期不符、UUID/Date 轉換失敗等）→ transaction rollback，**不寫入任何資料，也不標記 `coredata_import_done_v1`**。
- 下次啟動會重新偵測到「舊檔案存在 + 完成旗標未設置」，自動重試（因為 rollback 保證 Drift 端沒有殘留部分資料，重跑不會造成重複寫入，天然幂等）。
- 建議設一個重試上限（例如連續失敗 3 次），超過上限後：
  - 標記 `coredata_import_failed_permanently`，App 內顯示一個明確提示（例如「舊資料匯入失敗，請聯繫支援」），並保留一個手動「重試匯入」的按鈕（清掉這個旗標讓它可以再自動跑一次）。
  - 把詳細錯誤訊息（exception + stack trace + 進行到哪一張表）寫進本地 log 檔（純文字檔，不要只靠 `debugPrint`，release build 抓不到），方便日後使用者回報問題時能提供 log。

### 4.7 Android 端行為

Android 沒有舊資料，4.1 的檔案存在性判斷會自然回傳 false，直接標記完成並跳過，不需要任何額外分支。

---

## 5. 驗收測試設計

### 5.1 準備真實 fixture

1. 在模擬器上跑**目前上架的 iOS 版本**（舊 CoreData 版），手動建立一組涵蓋所有 entity 的代表性資料：
   - 幾筆 `workout`，每筆底下有多個 `workoutExercise`，每個 `workoutExercise` 底下有多組 `workoutSet`（確保多層巢狀關聯都有資料）
   - 幾筆 `bodyWeight`
   - 至少一個自訂 `exercise`（`isSystem = false`，`userId` 有值）
   - 至少一個自訂 `template` 及其 `templateExercise`
   - 至少一筆 `personalRecord`、一筆 `userGoal`、一筆 `powerLiftRecord`
   - 刻意涵蓋 optional 欄位為 nil（例如 `note`、`email`）和有值兩種情境
2. 讓 App 正常關閉一次（或手動觸發 WAL checkpoint），確保資料都 checkpoint 進主檔，再從模擬器沙盒抓出 `Library/Application Support/WorkoutRecord.sqlite`（連同 `-wal`/`-shm` 一起抓，即使已 checkpoint 過，匯入程式本來就要能處理帶 WAL 的情境，直接測試比較貼近實際情況）。
   - 取得模擬器沙盒路徑：`xcrun simctl get_app_container <device-id> com.mikelin.workitout data`，或在 Xcode 的 Devices and Simulators 視窗直接下載容器。
3. 把抓出的檔案放進 Flutter 專案，例如 `app/test/fixtures/coredata/WorkoutRecord.sqlite`（連同 `-wal`/`-shm`）。

### 5.2 測試設計

1. 寫一個 Dart test，把 fixture 路徑餵給匯入函式，跑過整個匯入流程，寫進一個全新的暫存 Drift database（不要污染真正的 App database）。
2. **筆數比對（對應「不遺失任何訓練歷史」這條硬性要求的量化驗證）**：對 fixture 直接用 `sqlite3` 下 `SELECT COUNT(*) FROM ZXXXENTITY`，跟匯入後 Drift 對應表的 `SELECT COUNT(*)` 逐表比對，**11 張表都必須完全一致**。
3. **抽樣欄位比對**：對每張表挑幾筆（第一筆、最後一筆、隨機幾筆），比對關鍵欄位：
   - UUID 轉字串是否正確（格式、大小寫）
   - Date 秒數 `+978307200` 換算是否正確（可以用已知的 `createdAt` 反推驗證）
   - Bool 0/1 對應是否正確
   - `weight`/`reps`/`volume` 等數值有沒有精度遺失
4. **關聯完整性檢查**：隨機挑幾個 `workout`，確認底下 `workoutExercise` 數量、每個 `workoutExercise` 底下 `workoutSet` 數量，匯入前後一致；且新 schema 裡的外鍵字串（`workoutId`/`workoutExerciseId` 等）真的能 join 回對應的 parent row。
5. **邊界情況測試**：
   - 空庫（全新安裝，`WorkoutRecord.sqlite` 不存在）→ 不報錯，直接標記完成。
   - 檔案存在但損毀/非預期格式（例如用亂數 binary 冒充 `.sqlite`）→ 匯入函式能優雅 catch 例外、不 crash 整個 App，並進入 4.6 的失敗重試邏輯。
   - optional 欄位為 NULL 的情況（`email`/`note` 為 nil）→ 轉換不因 null 而 crash。

---

## 附錄：調查中發現的落差與風險（給 Mike 和實作工人參考）

1. **兩份 `.xcdatamodeld` 並存**：只有 `ios/WorkoutRecord/WorkoutRecord/Sources/WorkoutRecord.xcdatamodeld` 是真正被編譯進 App 的版本（用 `PBXFileSystemSynchronizedRootGroup` 機制判斷），另一份 `ios/WorkoutRecord/WorkoutRecord.xcdatamodeld` 是孤兒舊檔，少了 `exerciseName`/`isCompleted`/`isCustomExercise` 三個屬性和整個 `PowerLiftRecordEntity`，不要誤用。
2. **`docs/DATABASE_SCHEMA.md` 是規劃中的 PostgreSQL 後端 schema，跟實際 iOS 本地 CoreData schema 有大量出入**，不能直接套用去寫匯入程式：
   - docs 有 `exercise_categories`、`user_exercise_settings` 兩張表，CoreData 完全沒有對應實體（`ExerciseEntity.categoryId` 只是一個游離的 UUID，沒有實體、沒有關聯約束，分類清單目前應該是寫死在 client 端程式碼裡）。
   - docs 的 `personal_records` 有 `record_type` 枚舉欄位（`1rm`/`max_weight`/`max_reps`/`max_volume`），CoreData 的 `PersonalRecordEntity` 沒有這個欄位，固定只記錄 1RM（`oneRepMax`/`reps`/`weight`）。
   - CoreData 多了 docs 完全沒提到的 `UserGoalEntity`（各肌群 volume 目標 + 每週訓練目標 + 休息日提醒）和 `PowerLiftRecordEntity`（三大項 PR 記錄），這兩個實體在實際 App 裡有真實資料，匯入時不能漏掉。
3. **CoreData 用「裸 UUID 屬性」（`userId`/`workoutId`/`exerciseId`…）做關聯，同時又平行存在正規 CoreData relationship**（例如 `WorkoutEntity` 同時有 `userId` 屬性又有 `user` relationship），這是歷史包袱造成的雙軌設計，兩邊理論上應該一致但沒有資料庫層級約束保證。寫轉換程式建議以「明確的 `xxxId` 屬性」為準，CoreData relationship 只是輔助參考。
4. **`GlobalSettings`（`GlobalSettingsManager.swift`）用一個藏在程式碼變數裡的 key**（`private let settingsKey = "GlobalSettings"`），單純 grep `forKey: "..."` 這種字面模式找不到，是這次調查裡少數需要跳出模式匹配、直接讀程式邏輯才找到的 key。
5. **同一批使用者偏好有多套並存、疑似重複的舊設計**：`AppSettings`（已標記 deprecated 但部分 `@AppStorage` key 仍實際生效）vs `GlobalSettingsManager`（JSON blob，目前主要生效邏輯）；`PrivacyPolicyView` 的 `PrivacyPolicyAccepted` vs `PrivacyConsentService` 的 `HasAgreedToPrivacy`，兩者各自獨立寫入、沒有互相同步。建議 Flutter 版隱私同意重新設計一套流程、要求使用者重新確認，而不是花力氣調和兩套不一致的舊旗標。
6. **`WorkoutRecordApp.swift` 有一段用 `CoreDataModelVersion` UserDefaults key 比對版本號（目前寫死 `"2.3"`）的邏輯，版本不符就會主動清空 Application Support/Documents/Library 三個目錄下的 `WorkoutRecord.sqlite*` 檔案重建空庫**。這代表現存使用者裝置上的 CoreData 內容，可能已經因為過去某次版本號變動被清空重建過，不保證是完整訓練歷史。這不是本次 CoreData→Flutter 移轉能處理的問題（只能匯入「現存」內容），但如果之後有使用者反映「怎麼感覺資料變少了」，根源很可能是這段舊邏輯，而不是這次移轉造成的，值得讓 Mike 知道。

---

最後更新：2026-07-22

## 附錄 B:真實 fixture 驗證結果(2026-07-22,大腦親自抽取)

以 Debug build 在 iPhone 17 Pro 模擬器首啟後抽出真實 DB,存於 `app/test/fixtures/`(WorkoutRecord.sqlite + -wal/-shm + schema_dump.sql)。首啟 seed:66 個內建動作、4 個系統模板(20 個模板動作)、1 測試用戶、1 體重、3 PR、3 powerlift 紀錄。

實測確認(以 `schema_dump.sql` 為最終基準,取代第 2 節的推測):
- 11 張 Z 前綴 entity 表,表名/多數欄名與推測一致
- **UUID 屬性一律是 BLOB**(16 bytes),匯入時需轉為標準 UUID 字串
- **ordered 關聯排序欄位為 `Z_FOK_TEMPLATE` / `Z_FOK_WORKOUT` / `Z_FOK_WORKOUTEXERCISE`**;另有 `ZORDERINDEX` 屬性可用,兩者以 ZORDERINDEX 為準、Z_FOK 為備援
- 日期欄型別標記 TIMESTAMP,值為 Core Data epoch(2001-01-01)秒數,+978307200 轉 Unix
- 關聯同時存在 Z_PK 整數外鍵(ZUSER/ZWORKOUT/…)與反正規化 UUID BLOB(ZUSERID/ZWORKOUTID/…),**匯入以 UUID BLOB 欄 join**
- 隱藏表 Z_PRIMARYKEY / Z_METADATA / Z_MODELCACHE 匯入時跳過
