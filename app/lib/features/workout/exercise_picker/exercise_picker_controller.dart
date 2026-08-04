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
//
// provider 存取慣例(code review 要求留註解說明,不做「全部改 watch」或
// 「全部改 read」的無腦統一):`build()` 內用 `ref.watch`——這是整個
// controller 唯一「建立訂閱」的地方,底下的 repository/db provider 若被
// override 替換(例如測試切換 fake repository),`build()` 需要重跑;其餘
// 方法(`selectCategory`/`toggleFavorite`/`addCustomExercise`/
// `_resolveUserId`)都是使用者操作觸發的一次性指令,用 `ref.read` 只取當下
// 快照,不建立額外訂閱——這兩者本來就該不同,故意不統一。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/uuid.dart';
import '../../../data/migration/coredata_importer_result.dart' show kCoreDataImportedUserIdKey;
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
///
/// **搜尋是全庫搜尋,會脫離目前選中的分類脈絡**(對齊 iOS
/// `ExercisePickerView`:`searchText` 非空時無視 `selectedCategory`,搜尋範圍
/// 一律是完整的 `allExercises`)——`isSearching` 為 true 時 `visibleExercises`
/// 不會被採用,`searchResults` 才是畫面實際顯示的清單;`selectedCategoryId`
/// 本身在搜尋期間維持不變(不會被清掉),清空搜尋字串後會直接回到清空前的
/// 分類選擇,不需要額外復原邏輯。
class ExercisePickerState {
  const ExercisePickerState({
    required this.allExercises,
    required this.favoriteIds,
    this.searchQuery = '',
    this.selectedCategoryId,
    this.categoryExercises = const [],
    this.categoryError,
    this.selectedIds = const {},
    this.isSubmittingCustomExercise = false,
    this.customExerciseError,
  });

  final List<Exercise> allExercises;
  final Set<String> favoriteIds;
  final String searchQuery;
  final String? selectedCategoryId;
  final List<Exercise> categoryExercises;

  /// 分類查詢失敗的訊息(code review major 1):`selectCategory` 呼叫
  /// `ExerciseRepository.fetchByCategory` 失敗時寫入這裡,UI 靠這個欄位浮出
  /// 提示,不是靜默吞掉。成功查詢一律清成 null。
  final String? categoryError;
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
    Object? categoryError = _unset,
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
      categoryError: identical(categoryError, _unset)
          ? this.categoryError
          : categoryError as String?,
      selectedIds: selectedIds ?? this.selectedIds,
      isSubmittingCustomExercise: isSubmittingCustomExercise ?? this.isSubmittingCustomExercise,
      customExerciseError: identical(customExerciseError, _unset)
          ? this.customExerciseError
          : customExerciseError as String?,
    );
  }
}

/// `copyWith` 用來分辨「沒傳這個參數」跟「明確傳 null 要清掉這個欄位」的哨兵值
/// (`selectedCategoryId`/`categoryError`/`customExerciseError` 三個欄位本身
/// 合法值就包含 null,不能用「傳 null 代表不變」的慣例,否則永遠清不掉)。
const Object _unset = Object();

class ExercisePickerController extends AsyncNotifier<ExercisePickerState> {
  /// `selectCategory` 的競態守門(code review major 1 第 2 點):使用者快速
  /// 連點兩個分類(A→B)時,若 A 的查詢比 B 晚回來,不能讓 A 的結果蓋掉 B。
  /// 每次呼叫先遞增這個計數器當作「這是第幾次呼叫」,查詢完成時只有仍是
  /// 「最新一次呼叫」才套用結果,較舊的呼叫直接丟棄——不需要額外取消
  /// 機制,`fetchByCategory` 本身照樣跑完,只是結果被忽略。
  int _categoryRequestId = 0;

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
  ///
  /// code review major 1 修正的兩個常備紀律問題:
  /// 1. `fetchByCategory` 可能拋錯(DB 忙碌等)——原本沒有 try/catch,呼叫端
  ///    (`_CategoryTabs` 的 `onTap`)又沒有 await 這個 Future,失敗會變成
  ///    unhandled async error、chip 選不上也沒有任何提示。現在錯誤寫進
  ///    `state.categoryError`,UI 靠這個欄位浮出提示。
  /// 2. 見 [_categoryRequestId] 的競態守門說明。
  Future<void> selectCategory(String? categoryId) async {
    final current = state.value;
    if (current == null) return;

    final requestId = ++_categoryRequestId;

    if (categoryId == null) {
      state = AsyncData(
        current.copyWith(
          selectedCategoryId: null,
          categoryExercises: const [],
          categoryError: null,
        ),
      );
      return;
    }

    try {
      final exercises = await ref.read(exerciseRepositoryProvider).fetchByCategory(categoryId);
      if (requestId != _categoryRequestId) return; // 已經有更新的請求,這次結果作廢。
      final latest = state.value;
      if (latest == null) return;
      state = AsyncData(
        latest.copyWith(
          selectedCategoryId: categoryId,
          categoryExercises: exercises,
          categoryError: null,
        ),
      );
    } catch (_) {
      if (requestId != _categoryRequestId) return; // 同上:舊請求的失敗也不該蓋掉新請求的畫面。
      final latest = state.value;
      if (latest == null) return;
      state = AsyncData(latest.copyWith(categoryError: '載入分類失敗,請稍後再試'));
    }
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
  ///
  /// 容忍失敗的做法(code review minor 1,「提示」與「明寫容忍」擇一,這裡
  /// 選後者):`setStringList` 失敗(拋例外或回傳 false)時把畫面還原成
  /// 切換前的最愛清單,不額外彈提示——最愛只是次要的個人化設定,不是會
  /// 遺失資料的寫入(使用者只要再點一次星號就能重試),為了這個場景加一整套
  /// SnackBar/inline error UI 不成比例;但「不處理」與「靜默吞掉導致畫面
  /// 與實際持久化狀態不一致」是兩回事,還原畫面狀態是必要的,不能省。
  Future<void> toggleFavorite(String exerciseId) async {
    final current = state.value;
    if (current == null) return;
    final previousFavoriteIds = current.favoriteIds;
    final next = {...previousFavoriteIds};
    if (!next.add(exerciseId)) next.remove(exerciseId);
    state = AsyncData(current.copyWith(favoriteIds: next));

    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final success = await prefs.setStringList(kFavoriteExerciseIdsKey, next.toList());
      if (!success) {
        final latest = state.value;
        if (latest != null) {
          state = AsyncData(latest.copyWith(favoriteIds: previousFavoriteIds));
        }
      }
    } catch (_) {
      final latest = state.value;
      if (latest != null) {
        state = AsyncData(latest.copyWith(favoriteIds: previousFavoriteIds));
      }
    }
  }

  /// 自訂動作快速新增(brief 功能規格 4)。成功後重新載入 `allExercises`,
  /// 讓新動作立即可搜尋/可選;若目前正選著某個分類且新動作屬於該分類,一併
  /// 重新查詢該分類清單,維持畫面即時反映(brief「狀態快取生命週期」紀律)。
  ///
  /// 失敗時不拋例外——錯誤訊息放進 state.customExerciseError,呼叫端(quick
  /// add 表單)靠這個欄位顯示錯誤,不是 fire-and-forget(brief 常備紀律)。
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
    final userId = await _resolveUserId();

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

  /// 解析目前使用者在 Drift `Users` 表裡「真的存在」的 row id——這裡插入的
  /// 是 `Exercises.userId`,該欄位有 FK 參照 `Users(id)`(見
  /// `data/db/tables.dart` 的 `Exercises.userId`),直接塞一個不存在的 id
  /// 會在 insert 當下 FK violation(code review major 3)。
  ///
  /// 解析順序比照兩個既有慣例組合而成:
  /// - `features/dashboard/dashboard_controller.dart` 的 `_resolveUserId`:
  ///   session 的登入 id 必須先經 `UserRepository.getById` 查證真的存在,
  ///   不能直接假設 session 裡的 id 就是 Users 表裡的 id。
  /// - `features/onboarding/onboarding_controller.dart` 的 `_ensureUserRow`
  ///   解析順序:登入 id 查無此人時,退回血緣 key
  ///   ([kCoreDataImportedUserIdKey])——CoreData 匯入的升級用戶,Users row
  ///   的 id 是這個 key 指向的既有 row,不是這次登入的 session id;兩者在
  ///   換過登入方式/裝置的情境下可以不同。
  ///
  /// 跟上述兩處的差異:這裡**只讀不寫**——查無此人時不像 `_ensureUserRow`
  /// 那樣新建一筆 Users row(選動作器的自訂動作新增不該有「順便建帳號」的
  /// 副作用),直接回傳 null(`Exercises.userId` 本就 nullable,合法)。
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

final exercisePickerControllerProvider =
    AsyncNotifierProvider.autoDispose<ExercisePickerController, ExercisePickerState>(
  ExercisePickerController.new,
);
