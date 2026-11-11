import Flutter
import UIKit

/// 舊版 iOS App 留在 `UserDefaults.standard` 的所有 key。**讀(getLegacy*)與刪
/// (clearLegacyUserDefaults)共用這一份**:新增要匯入的舊 key 時加在這裡,刪帳號就
/// 自動連它一起清,不會有讀得到卻刪不掉的殘留。
private enum LegacyKey {
  static let currentUserId = "CurrentUserId"
  static let globalSettings = "GlobalSettings"
  static let weightUnit = "weightUnit"
  static let theme = "theme"
  static let oneRMFormula = "oneRMFormula"
  static let enableHapticFeedback = "enableHapticFeedback"
  static let userName = "userName"
  static let userEmail = "userEmail"
  static let userGender = "userGender"
  static let userAge = "userAge"
  static let userHeight = "userHeight"
  static let userCurrentWeight = "userCurrentWeight"
  static let userTargetWeight = "userTargetWeight"
  static let weeklyWorkoutGoal = "weeklyWorkoutGoal"
  static let isDarkMode = "isDarkMode"
  static let reminderTime = "reminderTime"
  static let lastViewedAchievementsDate = "lastViewedAchievementsDate"
  static let unlockedAchievements = "UnlockedAchievements"
  static let accentColor = "accentColor"
  static let customExercises = "customExercises"
  static let appleIDUserID = "AppleIDUserID"
  // 舊版登入時另外寫入、新版不匯入但屬於個資的 key(AppleIDAuthService.swift)。
  static let appleIDUserName = "AppleIDUserName"
  static let appleIDUserEmail = "AppleIDUserEmail"

  /// 刪帳號時用明確清單刪(不掃前綴——UserDefaults.standard 也放著 Flutter/系統的 key)。
  static let all: [String] = [
    currentUserId,
    globalSettings,
    weightUnit,
    theme,
    oneRMFormula,
    enableHapticFeedback,
    userName,
    userEmail,
    userGender,
    userAge,
    userHeight,
    userCurrentWeight,
    userTargetWeight,
    weeklyWorkoutGoal,
    isDarkMode,
    reminderTime,
    lastViewedAchievementsDate,
    unlockedAchievements,
    accentColor,
    customExercises,
    appleIDUserID,
    appleIDUserName,
    appleIDUserEmail,
  ]
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    setUpLegacyPrefsChannel()
    return result
  }

  /// 讀取舊版 CoreData App(同 bundle ID)遺留在 `UserDefaults.standard`
  /// 裡的使用者偏好設定,供 Flutter 端 `LegacyPrefsImporter` 匯入。
  /// 詳見 docs/COREDATA_MIGRATION_SPEC.md 第 3 節。
  private func setUpLegacyPrefsChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "com.mikelin.workitout/legacy_prefs",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getLegacyPreferences":
        result(self?.readLegacyPreferences() ?? [:])
      case "getLegacyCustomExercises":
        result(self?.readLegacyCustomExercisesJson())
      case "getLegacyAppleUserId":
        result(self?.readLegacyAppleUserId())
      case "clearLegacyUserDefaults":
        self?.clearLegacyUserDefaults()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// 舊版登入時存的 Apple user identifier(UserDefaults `AppleIDUserID`,見
  /// ios/WorkoutRecord/.../AppleIDAuthService.swift)。同 team、同 bundle 下,
  /// 同一個 Apple ID 的新舊 identifier 相同,Flutter 端首次登入用它判斷本機的舊
  /// 資料是不是這個 Apple ID 的(共用裝置時不讓第一個登入者認領別人的資料)。
  /// 沒有這個 key 或為空字串回傳 nil。
  private func readLegacyAppleUserId() -> String? {
    guard let id = UserDefaults.standard.string(forKey: LegacyKey.appleIDUserID), !id.isEmpty else {
      return nil
    }
    return id
  }

  /// 刪帳號時清掉舊版留在 UserDefaults 的資料(Apple ID/姓名/信箱、個人資料、自訂動作、
  /// 成就等),照 [LegacyKey.all] 的明確清單逐個刪。
  private func clearLegacyUserDefaults() {
    let defaults = UserDefaults.standard
    for key in LegacyKey.all {
      defaults.removeObject(forKey: key)
    }
  }

  /// 舊版「自訂動作」存在 UserDefaults `customExercises`(`[Exercise]` 的
  /// JSONEncoder 輸出,不在 CoreData),原樣以 JSON 字串回傳,由 Dart 端
  /// `CoreDataImporter` 解析並以原 id 補寫進 exercises。沒有這個 key 回傳 nil。
  private func readLegacyCustomExercisesJson() -> String? {
    guard let data = UserDefaults.standard.data(forKey: LegacyKey.customExercises) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  private func readLegacyPreferences() -> [String: Any] {
    let defaults = UserDefaults.standard
    var payload: [String: Any] = [:]

    if let currentUserId = defaults.string(forKey: LegacyKey.currentUserId) {
      payload["currentUserId"] = currentUserId
    }

    // GlobalSettingsManager.swift 的 JSON blob(見 spec 附錄 4:key 藏在程式碼
    // 變數裡,不是常見的字面 forKey 字串)。
    if let globalSettingsData = defaults.data(forKey: LegacyKey.globalSettings),
       let json = String(data: globalSettingsData, encoding: .utf8) {
      payload["globalSettingsJson"] = json
    }

    // AppSettings(deprecated 但部分 @AppStorage key 仍實際生效)。
    if let weightUnit = defaults.string(forKey: LegacyKey.weightUnit) {
      payload["weightUnit"] = weightUnit
    }
    if let theme = defaults.string(forKey: LegacyKey.theme) {
      payload["theme"] = theme
    }
    if let oneRMFormula = defaults.string(forKey: LegacyKey.oneRMFormula) {
      payload["oneRMFormula"] = oneRMFormula
    }
    if defaults.object(forKey: LegacyKey.enableHapticFeedback) != nil {
      payload["enableHapticFeedback"] = defaults.bool(forKey: LegacyKey.enableHapticFeedback)
    }

    // UserProfile(非 deprecated,AppleIDAuthService 登入成功後仍會寫入)。
    if let userName = defaults.string(forKey: LegacyKey.userName) {
      payload["userName"] = userName
    }
    if let userEmail = defaults.string(forKey: LegacyKey.userEmail) {
      payload["userEmail"] = userEmail
    }
    if let userGender = defaults.string(forKey: LegacyKey.userGender) {
      payload["userGender"] = userGender
    }
    if defaults.object(forKey: LegacyKey.userAge) != nil {
      payload["userAge"] = defaults.integer(forKey: LegacyKey.userAge)
    }
    if defaults.object(forKey: LegacyKey.userHeight) != nil {
      payload["userHeight"] = defaults.double(forKey: LegacyKey.userHeight)
    }
    if defaults.object(forKey: LegacyKey.userCurrentWeight) != nil {
      payload["userCurrentWeight"] = defaults.double(forKey: LegacyKey.userCurrentWeight)
    }
    if defaults.object(forKey: LegacyKey.userTargetWeight) != nil {
      payload["userTargetWeight"] = defaults.double(forKey: LegacyKey.userTargetWeight)
    }
    if defaults.object(forKey: LegacyKey.weeklyWorkoutGoal) != nil {
      payload["weeklyWorkoutGoal"] = defaults.integer(forKey: LegacyKey.weeklyWorkoutGoal)
    }

    // 使用者體感相關。
    if defaults.object(forKey: LegacyKey.isDarkMode) != nil {
      payload["isDarkMode"] = defaults.bool(forKey: LegacyKey.isDarkMode)
    }
    if let reminderTime = defaults.object(forKey: LegacyKey.reminderTime) as? Date {
      payload["reminderTimeMillis"] = Int64(reminderTime.timeIntervalSince1970 * 1000)
    }
    if let lastViewed = defaults.object(forKey: LegacyKey.lastViewedAchievementsDate) as? Date {
      payload["lastViewedAchievementsDateMillis"] =
        Int64(lastViewed.timeIntervalSince1970 * 1000)
    }
    if let achievementsData = defaults.data(forKey: LegacyKey.unlockedAchievements),
       let json = String(data: achievementsData, encoding: .utf8) {
      payload["unlockedAchievementsJson"] = json
    }

    // accentColor:NSKeyedArchiver 編碼的 UIColor,原生端解出 RGBA 分量後
    // 直接回傳數值,Dart 端不需要自己解析二進位格式。
    if let accentColorData = defaults.data(forKey: LegacyKey.accentColor),
       let color = try? NSKeyedUnarchiver.unarchivedObject(
         ofClass: UIColor.self,
         from: accentColorData
       ) {
      var r: CGFloat = 0
      var g: CGFloat = 0
      var b: CGFloat = 0
      var a: CGFloat = 0
      color.getRed(&r, green: &g, blue: &b, alpha: &a)
      payload["accentColorR"] = Double(r)
      payload["accentColorG"] = Double(g)
      payload["accentColorB"] = Double(b)
      payload["accentColorA"] = Double(a)
    }

    return payload
  }
}
