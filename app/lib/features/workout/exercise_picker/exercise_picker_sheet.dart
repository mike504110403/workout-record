// 選動作器(波 3 第二段訓練核心流 + 模板編輯器共用的接縫元件)。對等 iOS
// `ios/WorkoutRecord/WorkoutRecord/Sources/Views/Exercise/ExercisePickerView.swift`
// + `ExercisePickerViewModel.swift`:分類瀏覽、即時搜尋、常用(最愛)動作、
// 自訂動作快速新增。
//
// 呈現形式選 modal bottom sheet(`isScrollControlled: true` 撐到接近全螢幕高
// 度)——手機平台最貼近 iOS `.sheet` 慣例,web/桌面視窗開這種高度撐滿的
// bottom sheet 也是常見、可用的型版,不需要為了 web 另外切一套 dialog 版型。
//
// 最愛「置頂或獨立分區」兩種做法 brief 都允許——這裡選「置頂」(不做獨立
// 「常用」分區):iOS 原始畫面本身也沒有真的渲染獨立的最愛分區(星號只是列表
// 項上的一個指示圖示),置頂排序已經達成「常用動作優先看到」的核心目的,
// 且不會讓同一個動作在畫面上出現兩次。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/exercise.dart';
import 'exercise_picker_categories.dart';
import 'exercise_picker_controller.dart';
import 'quick_add_exercise_sheet.dart';

/// 選動作器的公開契約。
///
/// - 單選(`multiSelect: false`,預設):點動作即回傳 `[exercise]` 並關閉。
/// - 多選(`multiSelect: true`):可勾選多個,按下確認鈕回傳清單。
/// - 取消(左上角按鈕或滑掉/點背景關閉):回傳 `null`。
Future<List<Exercise>?> showExercisePicker(
  BuildContext context, {
  bool multiSelect = false,
}) {
  return showModalBottomSheet<List<Exercise>?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ExercisePickerSheet(multiSelect: multiSelect),
  );
}

/// 選動作器的畫面本體。刻意 public(不加底線)——widget 測試需要直接
/// pump 它來驅動 [showExercisePicker] 觸發的 sheet 內容。
class ExercisePickerSheet extends ConsumerStatefulWidget {
  const ExercisePickerSheet({super.key, this.multiSelect = false});

  final bool multiSelect;

  @override
  ConsumerState<ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends ConsumerState<ExercisePickerSheet> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openQuickAdd() async {
    final created = await showQuickAddExerciseSheet(context);
    if (!mounted || created == null) return;

    if (widget.multiSelect) {
      // 多選模式沒有 iOS 對照行為(iOS 只有單選)——新增後把新動作直接勾選,
      // 但不關閉整個 sheet,讓使用者可以接著繼續勾其他動作再一起確認。
      ref.read(exercisePickerControllerProvider.notifier).toggleSelection(created.id);
      return;
    }

    // 單選模式對等 iOS `QuickAddExerciseSheet` 完成後的行為:新增即選取、
    // 直接關閉整個選動作器。
    Navigator.of(context).pop([created]);
  }

  void _selectSingle(Exercise exercise) {
    Navigator.of(context).pop([exercise]);
  }

  /// 多選確認:回傳清單依「`allExercises` ∪ `categoryExercises` 的查詢順序」
  /// 排列(先照 `allExercises` 的順序取出命中的,再補上只存在於
  /// `categoryExercises`、`allExercises` 沒有的),**不是使用者勾選的先後
  /// 順序**——契約沒有承諾回傳順序等於勾選順序,這裡先講清楚。
  ///
  /// code review major 2:原本只從 `allExercises` 解析勾選 id,但勾選動作
  /// 可能發生在分類篩選過的 `categoryExercises` 上——若這兩份清單的查詢
  /// 謂詞(`fetchAll` vs `fetchByCategory`)未來出現任何不一致,勾了的動作
  /// 會在確認當下無聲消失(id 在 `selectedIds` 裡,但在 `allExercises` 裡
  /// 找不到對應物件,`where` 直接跳過)。改成對兩份清單的聯集(依 id 去重)
  /// 解析,不管勾選當下畫面顯示的是哪一份清單都不會遺漏。
  void _confirmMultiSelect(ExercisePickerState state) {
    // `<String, Exercise>{}` 是 LinkedHashMap,保留插入順序——先塞
    // `allExercises`(fetchAll 依名稱排序的結果),再補只存在於
    // `categoryExercises`、`allExercises` 沒有的(理論上不會發生,但兩份
    // 清單來自不同查詢,防禦性地兜底)。`putIfAbsent` 確保重複 id 以先塞入
    // 的為準,不會被後面覆寫。
    final combined = <String, Exercise>{};
    for (final e in state.allExercises) {
      combined.putIfAbsent(e.id, () => e);
    }
    for (final e in state.categoryExercises) {
      combined.putIfAbsent(e.id, () => e);
    }
    final selected = combined.values.where((e) => state.selectedIds.contains(e.id)).toList();
    Navigator.of(context).pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(exercisePickerControllerProvider);
    final mediaQuery = MediaQuery.of(context);

    // 搜尋框打字時鍵盤會從螢幕底部升起(`viewInsets.bottom`)——sheet 高度
    // 是寫死的 `size.height * 0.9`,不會自動幫我們避開鍵盤(不像
    // `Scaffold(resizeToAvoidBottomInset: true)` 那樣的自動行為),外層再包
    // 一層 `Padding` 把整包內容往上推,鍵盤蓋住的是 sheet 底部空白而不是清單
    // 內容。quick_add_exercise_sheet.dart 的表單已經是這個做法,這裡補齊。
    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: SizedBox(
        height: mediaQuery.size.height * 0.9,
        child: SafeArea(
          child: Column(
            children: [
            _Header(onCancel: () => Navigator.of(context).pop(null), onAdd: _openQuickAdd),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                key: const Key('exercise_picker_search_field'),
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜尋動作',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          key: const Key('exercise_picker_clear_search_button'),
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            ref.read(exercisePickerControllerProvider.notifier).setSearchQuery('');
                            setState(() {});
                          },
                        ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (value) {
                  ref.read(exercisePickerControllerProvider.notifier).setSearchQuery(value);
                  setState(() {});
                },
              ),
            ),
            Expanded(
              child: asyncState.when(
                data: (state) => _Body(
                  state: state,
                  multiSelect: widget.multiSelect,
                  onSelectSingle: _selectSingle,
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('載入失敗:$error')),
              ),
            ),
            if (widget.multiSelect)
              asyncState.maybeWhen(
                data: (state) => _ConfirmBar(
                  state: state,
                  onConfirm: () => _confirmMultiSelect(state),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onCancel, required this.onAdd});

  final VoidCallback onCancel;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          TextButton(
            key: const Key('exercise_picker_cancel_button'),
            onPressed: onCancel,
            child: const Text('取消'),
          ),
          const Expanded(
            child: Text('選擇動作', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          IconButton(
            key: const Key('exercise_picker_add_button'),
            icon: const Icon(Icons.add),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.multiSelect, required this.onSelectSingle});

  final ExercisePickerState state;
  final bool multiSelect;
  final void Function(Exercise exercise) onSelectSingle;

  @override
  Widget build(BuildContext context) {
    if (state.isSearching) {
      final results = state.searchResults;
      if (results.isEmpty) {
        return _EmptyState(
          key: const Key('exercise_picker_empty_search'),
          icon: Icons.search_off,
          // trim 過的字串——搜尋框允許使用者打出前後帶空白的查詢(例如按了
          // 空白鍵才發現找不到東西),空狀態文案不該原樣把那些空白字元也
          // 顯示出來。
          title: '找不到「${state.searchQuery.trim()}」',
          subtitle: '試試其他關鍵字或新增自訂動作',
        );
      }
      return _ExerciseListView(
        exercises: results,
        state: state,
        multiSelect: multiSelect,
        onSelectSingle: onSelectSingle,
      );
    }

    return Column(
      children: [
        // 分類查詢失敗的提示(code review major 1):`selectCategory` 失敗時
        // 不改變 `selectedCategoryId`/`categoryExercises`(畫面停留在切換前
        // 的分類,不假裝切換成功),用這個 inline banner 告知使用者、不用
        // SnackBar——sheet 高度撐到螢幕 90%,SnackBar 從 `ScaffoldMessenger`
        // 找到的通常是背後那個被蓋住的 Scaffold,彈出來也可能整個看不到
        // (code review minor 3 同樣的顧慮)。
        if (state.categoryError != null)
          Container(
            key: const Key('exercise_picker_category_error'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.errorContainer,
            child: Text(
              state.categoryError!,
              style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
            ),
          ),
        _CategoryTabs(selectedCategoryId: state.selectedCategoryId),
        Expanded(
          child: state.visibleExercises.isEmpty
              ? const _EmptyState(
                  key: Key('exercise_picker_empty_category'),
                  icon: Icons.fitness_center,
                  title: '暫無動作',
                )
              : _ExerciseListView(
                  exercises: state.visibleExercises,
                  state: state,
                  multiSelect: multiSelect,
                  onSelectSingle: onSelectSingle,
                ),
        ),
      ],
    );
  }
}

class _CategoryTabs extends ConsumerWidget {
  const _CategoryTabs({required this.selectedCategoryId});

  final String? selectedCategoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(exercisePickerControllerProvider.notifier);

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _CategoryChip(
            key: const Key('category_chip_all'),
            label: '全部',
            isSelected: selectedCategoryId == null,
            onTap: () => controller.selectCategory(null),
          ),
          for (final category in kExercisePickerCategories)
            _CategoryChip(
              key: Key('category_chip_${category.id}'),
              label: category.name,
              isSelected: selectedCategoryId == category.id,
              onTap: () => controller.selectCategory(category.id),
            ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _ExerciseListView extends ConsumerWidget {
  const _ExerciseListView({
    required this.exercises,
    required this.state,
    required this.multiSelect,
    required this.onSelectSingle,
  });

  final List<Exercise> exercises;
  final ExercisePickerState state;
  final bool multiSelect;
  final void Function(Exercise exercise) onSelectSingle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(exercisePickerControllerProvider.notifier);

    // key 給測試用:分類 tab 本身也是一個橫向 ListView/Scrollable,測試裡
    // `scrollUntilVisible` 需要明確指到「這個」清單的 Scrollable,不能靠
    // `find.byType(Scrollable)` 隨便撿一個(未搜尋時畫面上同時有兩個
    // Scrollable)。
    return ListView.separated(
      key: const Key('exercise_picker_list'),
      itemCount: exercises.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final exercise = exercises[index];
        final isFavorite = state.favoriteIds.contains(exercise.id);
        final isSelected = state.selectedIds.contains(exercise.id);
        return _ExerciseTile(
          exercise: exercise,
          isFavorite: isFavorite,
          multiSelect: multiSelect,
          isSelected: isSelected,
          onToggleFavorite: () => controller.toggleFavorite(exercise.id),
          onTap: () {
            if (multiSelect) {
              controller.toggleSelection(exercise.id);
            } else {
              onSelectSingle(exercise);
            }
          },
        );
      },
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile({
    required this.exercise,
    required this.isFavorite,
    required this.multiSelect,
    required this.isSelected,
    required this.onToggleFavorite,
    required this.onTap,
  });

  final Exercise exercise;
  final bool isFavorite;
  final bool multiSelect;
  final bool isSelected;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if (exercise.nameEn != null && exercise.nameEn!.isNotEmpty) exercise.nameEn!,
      if (exercise.primaryMuscleGroup != null) exercise.primaryMuscleGroup!.displayName,
    ];
    // code review minor 4:原本寫死 `Colors.green`/`Colors.amber`,深色模式
    // 下配色跟主題其他地方脫節、對比度也沒經過驗證。改用當前 `colorScheme`
    // 的語意色階,亮/暗兩種主題都能自動取得對應的配色與可讀對比度。
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      key: Key('exercise_row_${exercise.id}'),
      leading: multiSelect
          ? Checkbox(
              key: Key('exercise_checkbox_${exercise.id}'),
              value: isSelected,
              onChanged: (_) => onTap(),
            )
          : null,
      title: Row(
        children: [
          Flexible(child: Text(exercise.name, overflow: TextOverflow.ellipsis)),
          if (!exercise.isSystem) ...[
            const SizedBox(width: 6),
            Container(
              key: Key('exercise_custom_badge_${exercise.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '自訂',
                style: TextStyle(color: colorScheme.onTertiaryContainer, fontSize: 11),
              ),
            ),
          ],
        ],
      ),
      subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' · ')),
      trailing: IconButton(
        key: Key('exercise_favorite_star_${exercise.id}'),
        icon: Icon(
          isFavorite ? Icons.star : Icons.star_border,
          color: isFavorite ? colorScheme.tertiary : null,
        ),
        onPressed: onToggleFavorite,
      ),
      onTap: onTap,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key, required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({required this.state, required this.onConfirm});

  final ExercisePickerState state;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const Key('exercise_picker_confirm_button'),
          onPressed: state.selectedIds.isEmpty ? null : onConfirm,
          child: Text('確認 (${state.selectedIds.length})'),
        ),
      ),
    );
  }
}
