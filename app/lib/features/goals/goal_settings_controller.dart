// 目標設定頁的資料組裝與存檔控制。
//
// userId 解析:照抄 features/stats/pr/pr_list_controller.dart 的
// `_resolveUserId`(session → UserRepository 查證 + CoreData 匯入血緣
// fallback)。這是已知的第六份複本(dashboard_controller.dart /
// body_weight_controller.dart 用的是較簡化版,pr_list_controller.dart、
// exercise_picker_controller.dart、powerlifting_controller.dart 各自也有
// 一份完整版)——brief 明定照抄不抽共用,不在本波處理這筆技術債。
//
// 存檔語意:UserGoal schema 除本頁呈現的兩欄(weeklyWorkoutGoal /
// targetWeight)外還有六肌群容量目標、restDayReminder 等欄位(本頁不呈現,
// 波 6 以後才有 UI)。存檔前一律重新 `fetchByUser` 拿最新的既有值,只覆寫
// 這兩個表單欄位、其餘欄位原樣帶入再 `createOrUpdate`——刻意不用
// `UserGoal.copyWith`:它對 `targetWeight` 是 `targetWeight ?? this.
// targetWeight` 語意(傳 null 代表「不改」),沒辦法用來把目標體重清空成
// null(同 body_weight_controller.dart 對 `BodyWeight.copyWith`/note 欄位
// 吃過的虧),這裡改成直接建構完整物件覆寫兩欄、其餘欄位帶原值。
//
// 快取生命週期:存檔成功後 `ref.invalidate` 三個 provider——
//   1. `dashboardControllerProvider`(本週目標進度卡)
//   2. `bodyWeightTabControllerProvider`(體重頁目標線,波 4 已接好)
//   3. 自己(`ref.invalidateSelf()`,review 打回 MAJOR S1 補上)——本 provider
//      也不是 autoDispose,不 invalidate 自己的話,使用者存檔返回、不重開
//      app 就再次進頁,`build()` 不會重跑,表單會用「存檔前」的舊快取
//      prefill;這時若使用者什麼欄位都沒改就直接按儲存,會把 DB 剛存好的
//      新值原樣覆蓋回舊值。
// 前兩者都不是 autoDispose:若當下有 active listener(頁面仍掛在 widget
// tree,例如 Dashboard 在本頁底下沒被卸載)invalidate 會讓它們重新查詢並
// 反映新值;若當下沒有 listener(例如尚未進過體重頁),下次有人 watch 時
// 本來就會重新 build(),invalidate 在那之前只是確保不留舊快取,沒有副作用。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/uuid.dart';
import '../../data/migration/coredata_importer_result.dart' show kCoreDataImportedUserIdKey;
import '../../data/models/user_goal.dart';
import '../../data/providers.dart';
import '../auth/session_controller.dart';
import '../auth/shared_preferences_provider.dart';
import '../dashboard/dashboard_controller.dart';
import '../stats/body_weight/body_weight_controller.dart';

class GoalSettingsState {
  const GoalSettingsState({this.weeklyWorkoutGoal = 0, this.targetWeight});

  /// 週訓練次數目標(0 = 未設定)。
  final int weeklyWorkoutGoal;

  /// 目標體重(kg,null = 未設定)。
  final double? targetWeight;
}

class GoalSettingsController extends AsyncNotifier<GoalSettingsState> {
  @override
  Future<GoalSettingsState> build() async {
    // 同 pr_list_controller.dart:watch 而非 read——換帳號時要用新 userId
    // 重新查詢,不留前帳號快取(帳號隔離波 2 已做,這裡只是不引入新的
    // 跨帳號快取,不需要額外處理換帳號情境本身)。
    ref.watch(sessionControllerProvider.select((s) => s.appleUserId));

    final userId = await _resolveUserId();
    if (userId == null) return const GoalSettingsState();

    final goal = await ref.read(userGoalRepositoryProvider).fetchByUser(userId);
    if (goal == null) return const GoalSettingsState();
    return GoalSettingsState(
      weeklyWorkoutGoal: goal.weeklyWorkoutGoal,
      targetWeight: goal.targetWeight,
    );
  }

  /// 存檔(對照 dashboard_controller.dart `recordBodyWeight` /
  /// body_weight_controller.dart `addEntry` 的失敗處理慣例:userId 解析不到
  /// 時拋例外而非靜默 return,呼叫端(GoalSettingsPage._save)的 try/catch
  /// 會顯示錯誤、解除 loading,不會誤以為存檔成功了照樣 pop)。
  Future<void> save({required int weeklyWorkoutGoal, double? targetWeight}) async {
    final userId = await _resolveUserId();
    if (userId == null) {
      throw StateError(
        'GoalSettingsController.save: 無法解析 userId'
        '(session 沒有已登入的 appleUserId,或 UserRepository.getById 查無此人)',
      );
    }

    final repo = ref.read(userGoalRepositoryProvider);
    final existing = await repo.fetchByUser(userId);
    final now = DateTime.now();
    final merged = UserGoal(
      id: existing?.id ?? generateUuidV4(),
      userId: userId,
      weeklyWorkoutGoal: weeklyWorkoutGoal,
      targetWeight: targetWeight,
      volumeGoals: existing?.volumeGoals ?? const VolumeGoals(),
      restDayReminder: existing?.restDayReminder ?? false,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await repo.createOrUpdate(merged);

    ref.invalidate(dashboardControllerProvider);
    ref.invalidate(bodyWeightTabControllerProvider);
    // review 打回(MAJOR S1):這個 provider 不是 autoDispose,先前存檔後沒
    // invalidate 自己——若使用者存檔返回、不重開 app 就再次進頁,`build()`
    // 不會重跑,表單會用「存檔前」的舊快取 prefill;若這時使用者什麼欄位
    // 都沒改就直接按儲存,會把 DB 剛存好的新值原樣覆蓋回舊值。
    ref.invalidateSelf();
  }

  /// 照抄 pr_list_controller.dart 的 `_resolveUserId`(第六份複本,brief 明定
  /// 不抽共用)。
  Future<String?> _resolveUserId() async {
    final userRepo = ref.read(userRepositoryProvider);

    final sessionUserId = ref.read(sessionControllerProvider).appleUserId;
    if (sessionUserId != null && sessionUserId.isNotEmpty) {
      final existing = await userRepo.getById(sessionUserId);
      if (existing != null) return existing.id;
    }

    final prefs = ref.read(sharedPreferencesProvider);
    final importedUserId = prefs.getString(kCoreDataImportedUserIdKey);
    if (importedUserId != null && importedUserId.isNotEmpty) {
      final imported = await userRepo.getById(importedUserId);
      if (imported != null) return imported.id;
    }

    return null;
  }
}

final goalSettingsControllerProvider =
    AsyncNotifierProvider<GoalSettingsController, GoalSettingsState>(GoalSettingsController.new);
