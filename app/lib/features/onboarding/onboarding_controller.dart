// Onboarding 精靈的表單草稿狀態 + 完成動作。對應 iOS 版
// `ios/WorkoutRecord/WorkoutRecord/Sources/Models/OnboardingState.swift`。
//
// 完成動作(對等 iOS `OnboardingState.complete()`)刻意保留同一條規則:
// 體重只在「可解析成 Double」時才寫入 user_current_weight / 建立初始
// BodyWeight 紀錄,不像頁面切換的 [OnboardingDraft.isWeightValid] 檢查那樣
// 強制——iOS 的「跳過教學」在任何一頁都能直接 complete(),不會補做體重
// 驗證,這裡照抄同一個行為(寬鬆完成、嚴格才能翻頁)。但 Users row 不受這條
// 規則管——不論有沒有填體重,complete() 都會確保有一筆 Users row,體重只是
// row 建好之後「要不要多記一筆 BodyWeight」的獨立決定,兩者不該綁在一起。
//
// key 命名對齊 app/lib/data/migration/legacy_prefs_importer.dart 已在寫的
// `legacy_user_*` / `legacy_weekly_workout_goal` 慣例,但去掉 `legacy_`
// 前綴——這裡寫的是「現在」的使用者資料,不是搬移舊資料,語意不同,不能共用
// 同一把 key(避免跟舊資料匯入互相覆蓋)。統一 `user_` 前綴也讓
// SessionController.signOut() 能用前綴掃描一次清掉所有 Onboarding 個資。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/uuid.dart';
import '../../data/migration/coredata_importer_result.dart'
    show kCoreDataImportedUserIdKey;
import '../../data/models/body_weight.dart';
import '../../data/providers.dart';
import '../auth/session_controller.dart';
import '../auth/shared_preferences_provider.dart';
import 'onboarding_status.dart';

const kUserGenderKey = 'user_gender';
const kUserAgeKey = 'user_age';
const kUserHeightKey = 'user_height';
const kUserCurrentWeightKey = 'user_current_weight';
const kUserTargetWeightKey = 'user_target_weight';
const kWeeklyWorkoutGoalKey = 'user_weekly_goal';
const kUserWeightUnitKey = 'user_weight_unit';

/// SessionController.signOut() 用來精準清除 Onboarding 個資的 key 清單——
/// 顯式列舉取代原本「掃描所有 `user_` 前綴 key」的隱式假設,哪些 key 算
/// Onboarding 個資由這裡明確定義。
const kOnboardingPersonalDataKeys = <String>[
  kUserGenderKey,
  kUserAgeKey,
  kUserHeightKey,
  kUserCurrentWeightKey,
  kUserTargetWeightKey,
  kWeeklyWorkoutGoalKey,
  kUserWeightUnitKey,
];

enum OnboardingWeightUnit {
  kg('kg'),
  lb('lb');

  const OnboardingWeightUnit(this.symbol);

  final String symbol;
}

/// lb -> kg,係數對齊 iOS `WeightFormatter`(`weight / 2.20462`)。
double _lbToKg(double lb) => lb / 2.20462;

class OnboardingDraft {
  const OnboardingDraft({
    this.weightText = '',
    this.weightUnit = OnboardingWeightUnit.kg,
    this.heightText = '',
    this.gender = '不指定',
    this.ageText = '',
    this.targetWeightText = '',
    this.weeklyGoal = 4,
  });

  final String weightText;
  final OnboardingWeightUnit weightUnit;
  final String heightText;
  final String gender;
  final String ageText;
  final String targetWeightText;
  final int weeklyGoal;

  /// 體重是否為有效數值——對等 iOS `canProceed(from: .basicInfo)`,用來擋
  /// 「下一步」,不是用來擋「跳過教學」。
  bool get isWeightValid => double.tryParse(weightText) != null;

  double? get _weightInKg {
    final value = double.tryParse(weightText);
    if (value == null) return null;
    return weightUnit == OnboardingWeightUnit.lb ? _lbToKg(value) : value;
  }

  double? get _targetWeightInKg {
    final value = double.tryParse(targetWeightText);
    if (value == null) return null;
    return weightUnit == OnboardingWeightUnit.lb ? _lbToKg(value) : value;
  }

  OnboardingDraft copyWith({
    String? weightText,
    OnboardingWeightUnit? weightUnit,
    String? heightText,
    String? gender,
    String? ageText,
    String? targetWeightText,
    int? weeklyGoal,
  }) {
    return OnboardingDraft(
      weightText: weightText ?? this.weightText,
      weightUnit: weightUnit ?? this.weightUnit,
      heightText: heightText ?? this.heightText,
      gender: gender ?? this.gender,
      ageText: ageText ?? this.ageText,
      targetWeightText: targetWeightText ?? this.targetWeightText,
      weeklyGoal: weeklyGoal ?? this.weeklyGoal,
    );
  }
}

class OnboardingController extends Notifier<OnboardingDraft> {
  @override
  OnboardingDraft build() => const OnboardingDraft();

  void setWeightText(String value) => state = state.copyWith(weightText: value);

  void setWeightUnit(OnboardingWeightUnit unit) => state = state.copyWith(weightUnit: unit);

  void setHeightText(String value) => state = state.copyWith(heightText: value);

  void setGender(String value) => state = state.copyWith(gender: value);

  void setAgeText(String value) => state = state.copyWith(ageText: value);

  void setTargetWeightText(String value) => state = state.copyWith(targetWeightText: value);

  void setWeeklyGoal(int value) => state = state.copyWith(weeklyGoal: value);

  /// 完成 Onboarding:寫入 prefs 個人資料、確保 Drift Users 表有使用者
  /// row、只有本次新建的使用者才記一筆初始 BodyWeight,最後標記完成旗標。
  ///
  /// 「只有新建才寫初始體重」是重複初始體重回歸修正(review
  /// 2026-07-30)——同帳號登出後 `has_completed_onboarding` 旗標被清掉,
  /// 重新登入再跑一次 Onboarding 精靈時,`_ensureUserRow` 會沿用既有 row
  /// (不是新建),此時不該再補一筆「初始體重」,那筆體重紀錄的語意是
  /// 「這個使用者第一次被建立時的體重」,沿用既有帳號不成立這個語意。
  Future<void> complete() async {
    final draft = state;
    final prefs = ref.read(sharedPreferencesProvider);

    final weightKg = draft._weightInKg;
    if (weightKg != null) {
      await prefs.setDouble(kUserCurrentWeightKey, weightKg);
    }

    final heightCm = double.tryParse(draft.heightText);
    if (heightCm != null) {
      await prefs.setDouble(kUserHeightKey, heightCm);
    }

    await prefs.setString(kUserGenderKey, draft.gender);

    final age = int.tryParse(draft.ageText);
    if (age != null) {
      await prefs.setInt(kUserAgeKey, age);
    }

    final targetWeightKg = draft._targetWeightInKg;
    if (targetWeightKg != null) {
      await prefs.setDouble(kUserTargetWeightKey, targetWeightKg);
    }

    await prefs.setInt(kWeeklyWorkoutGoalKey, draft.weeklyGoal);
    await prefs.setString(kUserWeightUnitKey, draft.weightUnit.symbol);

    final session = ref.read(sessionControllerProvider);
    final (:id, :isNewUser) = await _ensureUserRow(session);

    if (weightKg != null && isNewUser) {
      final now = DateTime.now();
      await ref.read(bodyWeightRepositoryProvider).create(
            BodyWeight(
              id: generateUuidV4(),
              userId: id,
              weight: weightKg,
              measuredAt: now,
              note: '初始體重',
              createdAt: now,
              updatedAt: now,
            ),
          );
    }

    await ref.read(onboardingStatusProvider.notifier).markCompleted();
  }

  /// 確保 Drift Users 表有使用者 row,回傳其 id 與「是否為本次新建」:
  /// - 優先用登入身分(Apple / 測試登入 user id)找既有 row,有就沿用
  ///   (isNewUser = false)。
  /// - 找不到時,只有在「這台裝置有 CoreData 匯入血緣」——`getById` 查
  ///   [kCoreDataImportedUserIdKey] 對應的 row,而且那筆 row 真的存在——
  ///   才允許沿用它(isNewUser = false)。這是升級用戶的防禦性回退,理論
  ///   上他們在 Onboarding 前就會被
  ///   [autoCompleteOnboardingForUpgradedUsersIfNeeded] 自動跳過,這裡只是
  ///   保險。沒有這個明確血緣訊號時絕不能沿用陌生的既有 row——否則換一個
  ///   帳號登入、或測試環境殘留舊資料時會直接吃到上一個人的資料。
  /// - 兩者都沒有,以登入身分(或新 UUID)新建一筆(isNewUser = true)。
  Future<({String id, bool isNewUser})> _ensureUserRow(SessionState session) async {
    final userRepo = ref.read(userRepositoryProvider);
    final desiredId = session.appleUserId;

    if (desiredId != null && desiredId.isNotEmpty) {
      final existing = await userRepo.getById(desiredId);
      if (existing != null) return (id: existing.id, isNewUser: false);
    }

    final prefs = ref.read(sharedPreferencesProvider);
    final importedUserId = prefs.getString(kCoreDataImportedUserIdKey);
    if (importedUserId != null && importedUserId.isNotEmpty) {
      final imported = await userRepo.getById(importedUserId);
      if (imported != null) return (id: imported.id, isNewUser: false);
    }

    final id = (desiredId != null && desiredId.isNotEmpty) ? desiredId : generateUuidV4();
    final isNewUser =
        await userRepo.ensure(id, name: session.appleUserName, email: session.appleUserEmail);
    return (id: id, isNewUser: isNewUser);
  }
}

final onboardingControllerProvider = NotifierProvider<OnboardingController, OnboardingDraft>(
  OnboardingController.new,
);
