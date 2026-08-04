// 選動作器的狀態控制。對照 iOS
// `ios/WorkoutRecord/WorkoutRecord/Sources/ViewModels/ExercisePickerViewModel.swift`,
// 但補完了 iOS 版沒做完的最愛持久化(iOS `toggleFavorite` 只改記憶體、留了
// 一句「TODO: 保存到 UserDefaults 或其他持久化存儲」;這裡真的存進
// SharedPreferences,brief 功能規格 3)。
//
// 用 `AsyncNotifierProvider.autoDispose`(對照專案既有 Notifier 慣例,見
// `features/dashboard/dashboard_controller.dart`/`features/auth/session_controller.dart`
// 手動宣告 provider,不用 code-gen)。刻意選 autoDispose——選動作器是一次性
// 彈出的 sheet,不是常駐頁面:sheet 關閉、widget 樹卸載、最後一個 watcher
// 消失後狀態就該丟棄,下次開啟重新呼叫 build() 全新查詢,不會夾帶上次開啟
// 遺留的搜尋字串/已選分類/多選勾選狀態(brief「狀態快取生命週期」紀律)。
// 最愛清單本身不受影響——它存在 SharedPreferences,不是 provider state,每次
// build() 都重新讀,持久化不會因為 autoDispose 而遺失。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/uuid.dart';
import '../../../data/models/exercise.dart';
import '../../../data/providers.dart';
import '../../auth/session_controller.dart';
import '../../auth/shared_preferences_provider.dart';

/// SharedPreferences 存最愛動作 id 清單的 key(裝置層級,String list)。
const kFavoriteExerciseIdsKey = 'favorite_exercise_ids';

/// 選動作器的畫面狀態快照。
///
/// `allExercises` 是開啟 sheet 當下(或新增自訂動作成功後)重新 `fetchAll()`
/// 的結果;`categoryExercises` 是選中分類時另外呼叫
/// `ExerciseRepository.fetchByCategory` 查到的結果,分類切換時整包替換,不做
/// 增量合併。
class ExercisePickerState {
  const ExercisePickerState({
    required this.allExercises,
    required this.favoriteIds,
    this.searchQuery = '',
    this.selectedCategoryId,
    this.categoryExercises = const [],
    this.selectedIds = const {},
    this.isSubmittingCustomExercise = false,
    this.customExerciseError,
  });

  final List<Exercise> allExercises;
  final Set<String> favoriteIds;
  final String searchQuery;
  final String? selectedCategoryId;
  final List<Exercise> categoryExercises;
  final Set<String> selectedIds;
  final bool isSubmittingCustomExercise;
  final String? customExerciseError;

  bool get isSearching => searchQuery.trim().isNotEmpty;

  /// 即時搜尋結果:純記憶體過濾(對照 iOS
  /// `ExercisePickerViewModel.searchExercises` 也是對已載入的 `allExercises`
  /// 做記憶體過濾,不重新打 DB)。範圍 = 中文名/英文名 + 主要肌群顯示名稱
  /// (肌群關鍵字,brief 功能規格 2)。一律套用「最愛置頂」排序。
  List<Exercise> get searchResults {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return const [];
    final matched = allExercises.where((e) => _matches(e, query)).toList();
    matched.sort(_compareFavoriteFirstThenName);
    return matched;
  }

  /// 目前該顯示的清單(未搜尋時用):選了分類 → 該分類查詢結果;否則 →
  /// 全部動作。一律套用「最愛置頂」排序(brief 功能規格 3:清單置頂)。
  List<Exercise> get visibleExercises {
    final base = selectedCategoryId != null ? categoryExercises : allExercises;
    final sorted = [...base]..sort(_compareFavoriteFirstThenName);
    return sorted;
  }

  bool _isFavorite(Exercise e) => favoriteIds.contains(e.id);

  int _compareFavoriteFirstThenName(Exercise a, Exercise b) {
    final aFav = _isFavorite(a);
    final bFav = _isFavorite(b);
    if (aFav != bFav) return aFav ? -1 : 1;
    return a.name.compareTo(b.name);
  }

  static bool _matches(Exercise e, String query) {
    if (e.name.toLowerCase().contains(query)) return true;
    if ((e.nameEn ?? '').toLowerCase().contains(query)) return true;
    final muscle = e.primaryMuscleGroup?.displayName.toLowerCase() ?? '';
    if (muscle.contains(query)) return true;
    return false;
  }

  ExercisePickerState copyWith({
    List<Exercise>? allExercises,
    Set<String>? favoriteIds,
    String? searchQuery,
    Object? selectedCategoryId = _unset,
    List<Exercise>? categoryExercises,
    Set<String>? selectedIds,
    bool? isSubmittingCustomExercise,
    Object? customExerciseError = _unset,
  }) {
    return ExercisePickerState(
      allExercises: allExercises ?? this.allExercises,
      favoriteIds: favoriteIds ?? this.favoriteIds,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategoryId: identical(selectedCategoryId, _unset)
          ? this.selectedCategoryId
          : selectedCategoryId as String?,
      categoryExercises: categoryExercises ?? this.categoryExercises,
      selectedIds: selectedIds ?? this.selectedIds,
      isSubmittingCustomExercise: isSubmittingCustomExercise ?? this.isSubmittingCustomExercise,
      customExerciseError: identical(customExerciseError, _unset)
          ? this.customExerciseError
          : customExerciseError as String?,
    );
  }
}

/// `copyWith` 用來分辨「沒傳這個參數」跟「明確傳 null 要清掉這個欄位」的哨兵值
/// (`selectedCategoryId`/`customExerciseError` 兩個欄位本身合法值就包含
/// null,不能用「傳 null 代表不變」的慣例,否則永遠清不掉)。
const Object _unset = Object();

class ExercisePickerController extends AsyncNotifier<ExercisePickerState> {
  @override
  Future<ExercisePickerState> build() async {
    final exercises = await ref.watch(exerciseRepositoryProvider).fetchAll();
    final prefs = ref.watch(sharedPreferencesProvider);
    final favoriteIds =
        (prefs.getStringList(kFavoriteExerciseIdsKey) ?? const <String>[]).toSet();
    return ExercisePickerState(allExercises: exercises, favoriteIds: favoriteIds);
  }

  void setSearchQuery(String query) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(searchQuery: query));
  }

  /// 分類瀏覽(brief 功能規格 1):`categoryId == null` 代表「全部」,回退到
  /// `allExercises`;否則呼叫 `ExerciseRepository.fetchByCategory` 查詢。
  Future<void> selectCategory(String? categoryId) async {
    final current = state.value;
    if (current == null) return;

    if (categoryId == null) {
      state = AsyncData(current.copyWith(selectedCategoryId: null, categoryExercises: const []));
      return;
    }

    final exercises = await ref.read(exerciseRepositoryProvider).fetchByCategory(categoryId);
    final latest = state.value;
    if (latest == null) return;
    state = AsyncData(
      latest.copyWith(selectedCategoryId: categoryId, categoryExercises: exercises),
    );
  }

  /// 多選模式下切換單一動作的勾選狀態。
  void toggleSelection(String exerciseId) {
    final current = state.value;
    if (current == null) return;
    final next = {...current.selectedIds};
    if (!next.add(exerciseId)) next.remove(exerciseId);
    state = AsyncData(current.copyWith(selectedIds: next));
  }

  /// 星號切換最愛(brief 功能規格 3):立即更新畫面(置頂排序即時反映),
  /// 再寫入 SharedPreferences 持久化。
  Future<void> toggleFavorite(String exerciseId) async {
    final current = state.value;
    if (current == null) return;
    final next = {...current.favoriteIds};
    if (!next.add(exerciseId)) next.remove(exerciseId);
    state = AsyncData(current.copyWith(favoriteIds: next));

    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setStringList(kFavoriteExerciseIdsKey, next.toList());
  }

  /// 自訂動作快速新增(brief 功能規格 4)。成功後重新載入 `allExercises`,
  /// 讓新動作立即可搜尋/可選;若目前正選著某個分類且新動作屬於該分類,一併
  /// 重新查詢該分類清單,維持畫面即時反映(brief「狀態快取生命週期」紀律)。
  ///
  /// 失敗時不拋例外——錯誤訊息放進 state.customExerciseError,呼叫端(quick
  /// add 表單)靠這個欄位彈 SnackBar,不是 fire-and-forget(brief 常備紀律)。
  /// 回傳建立成功的 [Exercise],失敗回傳 null。
  Future<Exercise?> addCustomExercise({
    required String name,
    String? nameEn,
    required String categoryId,
    required ExerciseType type,
  }) async {
    final current = state.value;
    if (current == null) return null;
    state = AsyncData(
      current.copyWith(isSubmittingCustomExercise: true, customExerciseError: null),
    );

    final now = DateTime.now();
    final session = ref.read(sessionControllerProvider);
    final appleUserId = session.appleUserId;
    final userId = (appleUserId != null && appleUserId.isNotEmpty) ? appleUserId : null;

    final exercise = Exercise(
      id: generateUuidV4(),
      name: name,
      nameEn: (nameEn == null || nameEn.trim().isEmpty) ? null : nameEn.trim(),
      categoryId: categoryId,
      type: type,
      isSystem: false,
      isActive: true,
      userId: userId,
      createdAt: now,
      updatedAt: now,
    );

    try {
      final repo = ref.read(exerciseRepositoryProvider);
      await repo.create(exercise);
      final refreshed = await repo.fetchAll();

      final latest = state.value ?? current;
      var categoryExercises = latest.categoryExercises;
      if (latest.selectedCategoryId == categoryId) {
        categoryExercises = await repo.fetchByCategory(categoryId);
      }

      state = AsyncData(
        latest.copyWith(
          allExercises: refreshed,
          categoryExercises: categoryExercises,
          isSubmittingCustomExercise: false,
          customExerciseError: null,
        ),
      );
      return exercise;
    } catch (_) {
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          isSubmittingCustomExercise: false,
          customExerciseError: '新增動作失敗,請稍後再試',
        ),
      );
      return null;
    }
  }
}

final exercisePickerControllerProvider =
    AsyncNotifierProvider.autoDispose<ExercisePickerController, ExercisePickerState>(
  ExercisePickerController.new,
);
