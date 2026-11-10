// 自定義動作管理的狀態控制。對照 iOS
// `ViewModels/CustomExerciseViewModel.swift`(列表/新增/編輯/刪除/名稱驗證)。
//
// 刪除語義(重要):一律走 [ExerciseRepository.delete](軟刪除,is_active = false),
// **不用** `permanentDelete`。理由:
// - `workout_exercises.exercise_id` / `template_exercises.exercise_id` 對
//   `exercises(id)` 沒有 on delete(= NO ACTION,雲端 schema 與 Drift 皆然,
//   Drift 另開了 foreign_keys pragma),被歷史訓練或模板引用的動作實體刪除會
//   FK violation,即使沒被引用也不可逆(見 `data/db/README.md` Review 追蹤事項)。
// - 歷史訓練/模板讀動作走 id 查詢(`fetchById`/PostgREST embed `exercises(*)`),
//   都不過濾 is_active,所以軟刪除後歷史紀錄與模板仍顯示動作名稱;選動作器、
//   分類瀏覽、搜尋的 `fetchAll`/`fetchByCategory`/`search` 都只回 is_active 的列,
//   所以軟刪除後新訓練選不到它。
//
// 狀態快取生命週期:provider 是 autoDispose,每次進頁面重新查詢;新增/編輯/
// 刪除成功後 [_afterMutation] 失效選動作器 provider,並刷新動作清單的離線快取
// (見該方法註解)。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/uuid.dart';
import '../../../data/models/exercise.dart';
import '../../../data/providers.dart';
import '../../auth/resolve_user_id.dart';
import '../../auth/session_controller.dart';
import '../../workout/exercise_picker/exercise_picker_controller.dart';

/// 動作名稱長度上限(對照 iOS `validateExerciseName`)。
const kCustomExerciseNameMinLength = 2;
const kCustomExerciseNameMaxLength = 50;

class CustomExercisesController extends AsyncNotifier<List<Exercise>> {
  @override
  Future<List<Exercise>> build() {
    ref.watch(sessionControllerProvider.select((s) => s.appleUserId));
    return ref.read(exerciseRepositoryProvider).getCustomExercises();
  }

  /// 名稱驗證(對照 iOS `validateExerciseName`:不可空白、2~50 字、不可與
  /// 既有自定義動作重名)。回傳錯誤訊息,合法回傳 null。編輯時傳
  /// [excludeId] 排除自己。
  String? validateName(String name, {String? excludeId}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '動作名稱不能為空';
    if (trimmed.length < kCustomExerciseNameMinLength) {
      return '動作名稱至少需要 $kCustomExerciseNameMinLength 個字符';
    }
    if (trimmed.length > kCustomExerciseNameMaxLength) {
      return '動作名稱不能超過 $kCustomExerciseNameMaxLength 個字符';
    }
    final existing = state.value ?? const <Exercise>[];
    if (existing.any((e) => e.id != excludeId && e.name == trimmed)) {
      return '此動作名稱已存在';
    }
    return null;
  }

  /// 新增自定義動作。失敗時往外拋(表單頁 try/catch 顯示錯誤、留在畫面重試)。
  Future<Exercise> create({
    required String name,
    required String categoryId,
    required ExerciseType type,
    PrimaryMuscleGroup? primaryMuscleGroup,
    MovementPattern? movementPattern,
    String? description,
  }) async {
    final now = DateTime.now();
    final exercise = Exercise(
      id: generateUuidV4(),
      name: name.trim(),
      categoryId: categoryId,
      type: type,
      primaryMuscleGroup: primaryMuscleGroup,
      movementPattern: movementPattern,
      description: _blankToNull(description),
      isSystem: false,
      isActive: true,
      // Supabase 實作會覆寫成 auth uid;Drift 需要 Users 表真的存在的 id(FK)。
      userId: await resolveSessionUserIdWithImportFallback(ref),
      createdAt: now,
      updatedAt: now,
    );
    await ref.read(exerciseRepositoryProvider).create(exercise);
    await _reload();
    await _afterMutation();
    return exercise;
  }

  /// 編輯自定義動作。直接組新的 [Exercise](不用 copyWith:copyWith 無法把
  /// 欄位清回 null,使用者把肌群改回「未選擇」或清空說明時會被誤判成沒傳)。
  /// 英文名稱不在表單裡(iOS 表單沒有),原值照抄保留。
  Future<void> updateExercise(
    Exercise existing, {
    required String name,
    required String categoryId,
    required ExerciseType type,
    PrimaryMuscleGroup? primaryMuscleGroup,
    MovementPattern? movementPattern,
    String? description,
  }) async {
    if (existing.isSystem) {
      throw StateError('系統動作不可編輯:${existing.id}');
    }
    await ref
        .read(exerciseRepositoryProvider)
        .update(
          Exercise(
            id: existing.id,
            name: name.trim(),
            nameEn: existing.nameEn,
            categoryId: categoryId,
            type: type,
            movementPattern: movementPattern,
            primaryMuscleGroup: primaryMuscleGroup,
            description: _blankToNull(description),
            videoUrl: existing.videoUrl,
            imageUrl: existing.imageUrl,
            isSystem: existing.isSystem,
            isActive: existing.isActive,
            userId: existing.userId,
            createdAt: existing.createdAt,
            updatedAt: DateTime.now(),
          ),
        );
    await _reload();
    await _afterMutation();
  }

  /// 刪除自定義動作(軟刪除,語義見檔頭)。畫面上先樂觀移除(滑動刪除的
  /// `Dismissible.onDismissed` 要求同一個 frame 內該項目就不在樹上),寫入失敗
  /// 則還原並往外拋。
  Future<void> deleteExercise(Exercise exercise) async {
    if (exercise.isSystem) {
      throw StateError('系統動作不可刪除:${exercise.id}');
    }
    final before = state.value;
    if (before != null) {
      state = AsyncData([
        for (final e in before)
          if (e.id != exercise.id) e,
      ]);
    }
    try {
      await ref.read(exerciseRepositoryProvider).delete(exercise.id);
    } catch (_) {
      if (before != null) state = AsyncData(before);
      rethrow;
    }
    await _afterMutation();
  }

  Future<void> _reload() async {
    state = AsyncData(await ref.read(exerciseRepositoryProvider).getCustomExercises());
  }

  /// 寫入成功後的收尾:
  /// 1. 失效選動作器 provider——它是 autoDispose,多半已不在樹上,但若仍存活
  ///    (例如從訓練中途開著的頁面堆疊)下次 watch 會重新 `fetchAll`。
  /// 2. 重新 `fetchAll()`:雲端模式的 [OfflineCachedExerciseRepository] 只在
  ///    `fetchAll` 成功時才更新離線快取;不刷新的話「刪除後馬上離線進選動作
  ///    器」會讀到含已刪動作的舊快取。盡力而為,失敗(離線)不影響已成功的寫入。
  Future<void> _afterMutation() async {
    ref.invalidate(exercisePickerControllerProvider);
    try {
      await ref.read(exerciseRepositoryProvider).fetchAll();
    } catch (_) {}
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}

final customExercisesControllerProvider =
    AsyncNotifierProvider.autoDispose<CustomExercisesController, List<Exercise>>(
      CustomExercisesController.new,
    );
