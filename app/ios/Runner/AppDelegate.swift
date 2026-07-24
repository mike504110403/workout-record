import Flutter
import UIKit

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
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func readLegacyPreferences() -> [String: Any] {
    let defaults = UserDefaults.standard
    var payload: [String: Any] = [:]

    if let currentUserId = defaults.string(forKey: "CurrentUserId") {
      payload["currentUserId"] = currentUserId
    }

    // GlobalSettingsManager.swift 的 JSON blob(見 spec 附錄 4:key 藏在程式碼
    // 變數裡,不是常見的字面 forKey 字串)。
    if let globalSettingsData = defaults.data(forKey: "GlobalSettings"),
       let json = String(data: globalSettingsData, encoding: .utf8) {
      payload["globalSettingsJson"] = json
    }

    // AppSettings(deprecated 但部分 @AppStorage key 仍實際生效)。
    if let weightUnit = defaults.string(forKey: "weightUnit") {
      payload["weightUnit"] = weightUnit
    }
    if let theme = defaults.string(forKey: "theme") {
      payload["theme"] = theme
    }
    if let oneRMFormula = defaults.string(forKey: "oneRMFormula") {
      payload["oneRMFormula"] = oneRMFormula
    }
    if defaults.object(forKey: "enableHapticFeedback") != nil {
      payload["enableHapticFeedback"] = defaults.bool(forKey: "enableHapticFeedback")
    }

    // UserProfile(非 deprecated,AppleIDAuthService 登入成功後仍會寫入)。
    if let userName = defaults.string(forKey: "userName") {
      payload["userName"] = userName
    }
    if let userEmail = defaults.string(forKey: "userEmail") {
      payload["userEmail"] = userEmail
    }
    if let userGender = defaults.string(forKey: "userGender") {
      payload["userGender"] = userGender
    }
    if defaults.object(forKey: "userAge") != nil {
      payload["userAge"] = defaults.integer(forKey: "userAge")
    }
    if defaults.object(forKey: "userHeight") != nil {
      payload["userHeight"] = defaults.double(forKey: "userHeight")
    }
    if defaults.object(forKey: "userCurrentWeight") != nil {
      payload["userCurrentWeight"] = defaults.double(forKey: "userCurrentWeight")
    }
    if defaults.object(forKey: "userTargetWeight") != nil {
      payload["userTargetWeight"] = defaults.double(forKey: "userTargetWeight")
    }
    if defaults.object(forKey: "weeklyWorkoutGoal") != nil {
      payload["weeklyWorkoutGoal"] = defaults.integer(forKey: "weeklyWorkoutGoal")
    }

    // 使用者體感相關。
    if defaults.object(forKey: "isDarkMode") != nil {
      payload["isDarkMode"] = defaults.bool(forKey: "isDarkMode")
    }
    if let reminderTime = defaults.object(forKey: "reminderTime") as? Date {
      payload["reminderTimeMillis"] = Int64(reminderTime.timeIntervalSince1970 * 1000)
    }
    if let lastViewed = defaults.object(forKey: "lastViewedAchievementsDate") as? Date {
      payload["lastViewedAchievementsDateMillis"] =
        Int64(lastViewed.timeIntervalSince1970 * 1000)
    }
    if let achievementsData = defaults.data(forKey: "UnlockedAchievements"),
       let json = String(data: achievementsData, encoding: .utf8) {
      payload["unlockedAchievementsJson"] = json
    }

    // accentColor:NSKeyedArchiver 編碼的 UIColor,原生端解出 RGBA 分量後
    // 直接回傳數值,Dart 端不需要自己解析二進位格式。
    if let accentColorData = defaults.data(forKey: "accentColor"),
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
