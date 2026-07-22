# 2026-07-22 — 移除 v1.2 未驗證的 Firestore users 同步

## 背景

v1.2 未 commit 的改動在 `AppleIDAuthService` 新增 `syncToFirebase` / `loadUserDataFromFirebase`:直接以 Apple 提供的 user ID 為文件路徑,把姓名/Email 寫入 Firestore `users/{id}`。安全審查判定 Critical:app 從未執行 `Auth.auth().signIn`(無 identityToken/nonce 驗證),寫入要成功資料庫規則必為開放,任何人抽出 IPA 中的 Firebase 設定即可越權讀寫全部用戶資料。另 Apple 登入狀態僅存 UserDefaults 明文,可偽造。

查證:此同步為 v1.2 新增,**線上版無此功能,用戶資料未實際暴露**。

## 選項

- A:整段移除 users 同步,登入保留、資料純本地;正規 Firebase Auth 留給 Flutter 版(firebase_auth 套件)實作。
- B:立即補完整 Firebase Auth(nonce + identityToken + signIn + Keychain + 規則收緊)——工程量大,且 Flutter 版要重做一次。

## 選擇:A

配套:Firebase console 的 Firestore Rules 需確認非 test mode;`app_config` 集合設唯讀(`allow read: if true; allow write: if false`),analytics 集合維持只寫不讀,其餘 deny(參考 `Sources/Utils/FirebaseSecurityRules.swift`)。

## 反悔訊號

- Flutter 版之前若必須先做任何雲端個資功能 → 必須先補正規 Auth,不得沿用未驗證寫入。

## 複核更正與遺留待辦(2026-07-22 安全複核)

正確表述:**已移除「登入身分個資」的雲端寫入**;仍保留假名化行為分析上傳(隨機 UUID、受 PrivacyConsentService 同意閘門,不含姓名/Email,與 Apple 識別碼無關聯)。

- (high)analytics 集合的 Firestore 規則為匿名公開可寫(`allow write: if request.auth == null`)→ 可被灌爆帳單/污染資料。既有問題,待 console 收緊或 App Check。
- (medium)死碼 `UserPreferencesSyncService.swift`、`FirebaseSetupChecker.swift` 內仍存未認證寫入路徑,誤接回會復活成 Critical,建議刪檔。
- (low)`ComprehensiveAnalyticsService.swift:331` 的 print 未包 `#if DEBUG`。
