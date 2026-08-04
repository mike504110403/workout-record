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

  void _confirmMultiSelect(ExercisePickerState state) {
    final selected = state.allExercises.where((e) => state.selectedIds.contains(e.id)).toList();
    Navigator.of(context).pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(exercisePickerControllerProvider);
    final mediaQuery = MediaQuery.of(context);

    return SizedBox(
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
          title: '找不到「${state.searchQuery}」',
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
        _CategoryTabs(selectedCategoryId: state.selectedCategoryId),
        Expanded(
          child: state.visibleExercises.isEmpty
              ? const _EmptyState(
                  key: Key('exercise_picker_empty_category'),
                  icon: Icons.fitness_center,
                  title: '暫無動作',
                  subtitle: null,
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
                color: Colors.green,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('自訂', style: TextStyle(color: Colors.white, fontSize: 11)),
            ),
          ],
        ],
      ),
      subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' · ')),
      trailing: IconButton(
        key: Key('exercise_favorite_star_${exercise.id}'),
        icon: Icon(isFavorite ? Icons.star : Icons.star_border, color: isFavorite ? Colors.amber : null),
        onPressed: onToggleFavorite,
      ),
      onTap: onTap,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key, required this.icon, required this.title, required this.subtitle});

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
