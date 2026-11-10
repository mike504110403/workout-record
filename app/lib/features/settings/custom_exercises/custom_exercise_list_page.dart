// 自定義動作列表頁。對照 iOS `Views/Exercise/CustomExerciseListView.swift`:
// 只列使用者自己建立的動作(系統動作不列)、右上角「+」新增、點鉛筆編輯、
// 左滑刪除(先確認)。刪除語義見 custom_exercises_controller.dart 檔頭。
//
// 狀態快取生命週期:watch autoDispose 的 customExercisesControllerProvider,每次
// 進頁面重新查詢;新增/編輯/刪除後 controller 自己更新 state 並失效選動作器。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/exercise.dart';
import 'custom_exercise_form_page.dart';
import 'custom_exercises_controller.dart';
import 'delete_exercise_dialog.dart';

class CustomExerciseListPage extends ConsumerWidget {
  const CustomExerciseListPage({super.key});

  Future<void> _openForm(BuildContext context, {Exercise? existing}) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => CustomExerciseFormPage(existing: existing)),
    );
  }

  Future<void> _deleteAfterSwipe(BuildContext context, WidgetRef ref, Exercise exercise) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(customExercisesControllerProvider.notifier).deleteExercise(exercise);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('刪除動作失敗,請稍後再試')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercisesAsync = ref.watch(customExercisesControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('自定義動作'),
        actions: [
          IconButton(
            key: const Key('customExerciseAddButton'),
            icon: const Icon(Icons.add),
            onPressed: () => _openForm(context),
          ),
        ],
      ),
      body: exercisesAsync.when(
        data: (exercises) {
          if (exercises.isEmpty) {
            return const _EmptyState();
          }
          return ListView(
            children: [
              for (final exercise in exercises)
                Dismissible(
                  key: ValueKey('customExerciseDismiss_${exercise.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (_) => confirmDeleteExercise(context, exercise),
                  onDismissed: (_) => _deleteAfterSwipe(context, ref, exercise),
                  child: _ExerciseTile(
                    exercise: exercise,
                    onEdit: () => _openForm(context, existing: exercise),
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('載入自定義動作失敗'),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('customExerciseRetryButton'),
                onPressed: () => ref.invalidate(customExercisesControllerProvider),
                child: const Text('重試'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('customExerciseEmptyState'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fitness_center, size: 60, color: Colors.grey),
            const SizedBox(height: 16),
            Text('還沒有自定義動作', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '點擊右上角的 + 來創建你的第一個自定義動作',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile({required this.exercise, required this.onEdit});

  final Exercise exercise;
  final VoidCallback onEdit;

  static Color _muscleColor(PrimaryMuscleGroup? group) {
    switch (group) {
      case PrimaryMuscleGroup.chest:
        return Colors.red;
      case PrimaryMuscleGroup.back:
        return Colors.blue;
      case PrimaryMuscleGroup.legs:
        return Colors.green;
      case PrimaryMuscleGroup.shoulders:
        return Colors.orange;
      case PrimaryMuscleGroup.arms:
        return Colors.purple;
      case PrimaryMuscleGroup.core:
        return Colors.amber;
      case PrimaryMuscleGroup.glutes:
        return Colors.pink;
      case PrimaryMuscleGroup.fullBody:
      case null:
        return Colors.grey;
    }
  }

  static IconData _typeIcon(ExerciseType type) {
    switch (type) {
      case ExerciseType.freeWeight:
        return Icons.fitness_center;
      case ExerciseType.machine:
        return Icons.settings;
      case ExerciseType.bodyweight:
        return Icons.directions_walk;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _muscleColor(exercise.primaryMuscleGroup);
    return ListTile(
      key: Key('customExerciseTile_${exercise.id}'),
      // Dismissible 的背景是紅色;tile 自己要有不透明底色,滑動時才不會透出紅色。
      tileColor: Theme.of(context).scaffoldBackgroundColor,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.2),
        child: Icon(_typeIcon(exercise.type), color: color),
      ),
      title: Text(exercise.name),
      subtitle: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          if (exercise.primaryMuscleGroup != null)
            _Tag(exercise.primaryMuscleGroup!.displayName, color),
          if (exercise.movementPattern != null)
            _Tag(exercise.movementPattern!.displayName, Colors.blue),
          _Tag(exercise.type.displayName, Colors.grey),
        ],
      ),
      trailing: IconButton(
        key: Key('customExerciseEditButton_${exercise.id}'),
        icon: const Icon(Icons.edit, color: Colors.blue),
        onPressed: onEdit,
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
    );
  }
}
