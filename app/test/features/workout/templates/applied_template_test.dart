// applyTemplate 純函式單元測試。參照值手算(brief 範例:3 動作 x
// suggestedSets 3 -> 9 組、重量全 0、次數 = suggestedReps),獨立於
// applied_template.dart 本身的實作邏輯計算,不是把同一段公式再抄一遍。
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/data/models/exercise.dart';
import 'package:workout_record/data/models/workout_template.dart';
import 'package:workout_record/features/workout/templates/applied_template.dart';

Exercise _buildExercise(String id, String name) {
  final now = DateTime.now();
  return Exercise(
    id: id,
    name: name,
    categoryId: 'cat-1',
    type: ExerciseType.freeWeight,
    createdAt: now,
    updatedAt: now,
  );
}

TemplateExercise _buildTemplateExercise({
  required String id,
  required String templateId,
  required Exercise exercise,
  int? suggestedSets,
  int? suggestedReps,
}) {
  return TemplateExercise(
    id: id,
    templateId: templateId,
    exerciseId: exercise.id,
    exercise: exercise,
    suggestedSets: suggestedSets,
    suggestedReps: suggestedReps,
  );
}

WorkoutTemplate _buildTemplate({
  required String id,
  required List<TemplateExercise> exercises,
}) {
  final now = DateTime.now();
  return WorkoutTemplate(
    id: id,
    userId: 'user-1',
    name: '測試模板',
    exercises: exercises,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('3 個動作,suggestedSets 皆為 3 -> 每動作 3 組、共 9 組,重量全 0,次數 = suggestedReps', () {
    final exerciseA = _buildExercise('ex-a', '深蹲');
    final exerciseB = _buildExercise('ex-b', '臥推');
    final exerciseC = _buildExercise('ex-c', '硬舉');
    final template = _buildTemplate(
      id: 'template-1',
      exercises: [
        _buildTemplateExercise(
            id: 'te-1', templateId: 'template-1', exercise: exerciseA, suggestedSets: 3, suggestedReps: 8),
        _buildTemplateExercise(
            id: 'te-2', templateId: 'template-1', exercise: exerciseB, suggestedSets: 3, suggestedReps: 10),
        _buildTemplateExercise(
            id: 'te-3', templateId: 'template-1', exercise: exerciseC, suggestedSets: 3, suggestedReps: 5),
      ],
    );

    final applied = applyTemplate(template);

    expect(applied.templateId, 'template-1');
    expect(applied.templateName, '測試模板');
    expect(applied.exercises, hasLength(3));

    // 手算參照值:9 組(3 動作 x 3 組),重量全 0,次數各自對照 suggestedReps。
    final totalSets = applied.exercises.fold<int>(0, (sum, e) => sum + e.sets.length);
    expect(totalSets, 9);
    expect(applied.exercises.every((e) => e.sets.every((s) => s.weight == 0)), isTrue);

    expect(applied.exercises[0].exerciseId, 'ex-a');
    expect(applied.exercises[0].exerciseName, '深蹲');
    expect(applied.exercises[0].sets, hasLength(3));
    expect(applied.exercises[0].sets.every((s) => s.reps == 8), isTrue);

    expect(applied.exercises[1].sets, hasLength(3));
    expect(applied.exercises[1].sets.every((s) => s.reps == 10), isTrue);

    expect(applied.exercises[2].sets, hasLength(3));
    expect(applied.exercises[2].sets.every((s) => s.reps == 5), isTrue);
  });

  test(
      'code-M2(已裁:對齊 iOS)suggestedSets 為 null 時預設 3 組——對齊 '
      'EnhancedWorkoutFlowView.swift:584 的 `?? 3`,不是先前版本的 `?? 0`', () {
    final exercise = _buildExercise('ex-a', '深蹲');
    final template = _buildTemplate(
      id: 'template-2',
      exercises: [
        _buildTemplateExercise(id: 'te-1', templateId: 'template-2', exercise: exercise),
      ],
    );

    final applied = applyTemplate(template);

    expect(applied.exercises.single.sets, hasLength(3));
  });

  test(
      'code-M2(已裁:對齊 iOS)suggestedReps 為 null 時,組的 reps 全部預設 10——'
      '對齊 EnhancedWorkoutFlowView.swift:589 的 `?? 10`', () {
    final exercise = _buildExercise('ex-a', '深蹲');
    final template = _buildTemplate(
      id: 'template-3',
      exercises: [
        _buildTemplateExercise(
          id: 'te-1',
          templateId: 'template-3',
          exercise: exercise,
          suggestedSets: 2,
        ),
      ],
    );

    final applied = applyTemplate(template);

    expect(applied.exercises.single.sets, hasLength(2));
    expect(applied.exercises.single.sets.every((s) => s.reps == 10), isTrue);
  });

  test('TemplateExercise.exercise 未掛載(null)時,exerciseName 退回空字串而不是拋錯', () {
    final template = _buildTemplate(
      id: 'template-4',
      exercises: [
        TemplateExercise(
          id: 'te-1',
          templateId: 'template-4',
          exerciseId: 'ex-missing',
          suggestedSets: 1,
          suggestedReps: 5,
        ),
      ],
    );

    final applied = applyTemplate(template);

    expect(applied.exercises.single.exerciseId, 'ex-missing');
    expect(applied.exercises.single.exerciseName, '');
    expect(applied.exercises.single.sets, hasLength(1));
  });

  test('沒有任何動作的模板 -> 回傳空 exercises 清單', () {
    final template = _buildTemplate(id: 'template-5', exercises: const []);

    final applied = applyTemplate(template);

    expect(applied.exercises, isEmpty);
  });
}
