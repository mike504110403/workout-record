// Onboarding 精靈的表單草稿狀態 + 完成動作。對應 iOS 版
// `ios/WorkoutRecord/WorkoutRecord/Sources/Models/OnboardingState.swift`。
//
// 完成動作(對等 iOS `OnboardingState.complete()`)刻意保留同一條規則:
// 體重只在「可解析成 Double」時才寫入 / 建立初始 BodyWeight 紀錄,不像
// 頁面切換的 [OnboardingDraft.isWeightValid] 檢查那樣強制——iOS 的「跳過
// 教學」在任何一頁都能直接 complete(),不會補做體重驗證,這裡照抄同一個
// 行為(寬鬆完成、嚴格才能翻頁)。
//
// key 命名對齊 app/lib/data/migration/legacy_prefs_importer.dart 已在寫的
// `legacy_user_*` / `legacy_weekly_workout_goal` 慣例,但去掉 `legacy_`
// 前綴——這裡寫的是「現在」的使用者資料,不是搬移舊資料,語意不同,不能共用
// 同一把 key(避免跟舊資料匯入互相覆蓋)。
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart' as db;
import '../../data/models/body_weight.dart';
import '../../data/providers.dart';
import '../auth/session_controller.dart';
import '../auth/shared_preferences_provider.dart';
import 'onboarding_status.dart';
import 'uuid.dart';

const kUserGenderKey = 'user_gender';
const kUserAgeKey = 'user_age';
const kUserHeightKey = 'user_height';
const kUserCurrentWeightKey = 'user_current_weight';
const kUserTargetWeightKey = 'user_target_weight';
const kWeeklyWorkoutGoalKey = 'weekly_workout_goal';
const kUserWeightUnitKey = 'user_weight_unit';

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
  /// row、有體重值才記一筆初始 BodyWeight,最後標記完成旗標。
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

    if (weightKg != null) {
      final database = ref.read(appDatabaseProvider);
      final session = ref.read(sessionControllerProvider);
      final userId = await _ensureUserRow(database, session);

      final now = DateTime.now();
      await ref.read(bodyWeightRepositoryProvider).create(
            BodyWeight(
              id: generateUuidV4(),
              userId: userId,
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

  /// 確保 Drift Users 表有使用者 row:優先用登入身分(Apple user id)當
  /// 主鍵新建;若表裡已有資料(理論上升級用戶會在 Onboarding 前就被自動
  /// 跳過,這裡是防禦性回退),沿用既有的第一筆,對等 CoreData 單一使用者
  /// 模型。
  Future<String> _ensureUserRow(db.AppDatabase database, SessionState session) async {
    final desiredId = session.appleUserId;
    if (desiredId != null && desiredId.isNotEmpty) {
      final existing =
          await (database.select(database.users)..where((t) => t.id.equals(desiredId)))
              .getSingleOrNull();
      if (existing != null) return existing.id;
    }

    final anyExisting =
        await (database.select(database.users)..limit(1)).getSingleOrNull();
    if (anyExisting != null) return anyExisting.id;

    final id = (desiredId != null && desiredId.isNotEmpty) ? desiredId : generateUuidV4();
    final now = DateTime.now();
    await database.into(database.users).insert(
          db.UsersCompanion.insert(
            id: id,
            name: Value(session.appleUserName),
            email: Value(session.appleUserEmail),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }
}

final onboardingControllerProvider = NotifierProvider<OnboardingController, OnboardingDraft>(
  OnboardingController.new,
);
