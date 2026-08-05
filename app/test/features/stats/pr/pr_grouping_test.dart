// pr_grouping.dart 的純函式單元測試:輸入刻意模擬
// PersonalRecordRepository.getPRSummary 已排序好的順序,驗證分組結果。

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/data/models/exercise.dart';
import 'package:workout_record/data/models/personal_record.dart';
import 'package:workout_record/features/stats/pr/pr_grouping.dart';

PRSummary _summary({
  required String exerciseId,
  required String exerciseName,
  PrimaryMuscleGroup? muscleGroup,
}) {
  return PRSummary(exerciseId: exerciseId, exerciseName: exerciseName, primaryMuscleGroup: muscleGroup);
}

void main() {
  group('groupByMuscleGroup', () {
    test('連續同肌群的項目收攏成同一區塊,保留輸入順序', () {
      final summaries = [
        _summary(exerciseId: 'e1', exerciseName: '槓鈴臥推', muscleGroup: PrimaryMuscleGroup.chest),
        _summary(exerciseId: 'e2', exerciseName: '上斜臥推', muscleGroup: PrimaryMuscleGroup.chest),
        _summary(exerciseId: 'e3', exerciseName: '深蹲', muscleGroup: PrimaryMuscleGroup.legs),
      ];

      final sections = groupByMuscleGroup(summaries);

      expect(sections.length, 2);
      expect(sections[0].muscleGroup, PrimaryMuscleGroup.chest);
      expect(sections[0].label, '胸');
      expect(sections[0].summaries.map((s) => s.exerciseId).toList(), ['e1', 'e2']);
      expect(sections[1].muscleGroup, PrimaryMuscleGroup.legs);
      expect(sections[1].summaries.map((s) => s.exerciseId).toList(), ['e3']);
    });

    test('沒有主要肌群的動作歸入「未分類」區塊', () {
      final summaries = [
        _summary(exerciseId: 'e1', exerciseName: '自訂動作', muscleGroup: null),
      ];

      final sections = groupByMuscleGroup(summaries);

      expect(sections.length, 1);
      expect(sections[0].muscleGroup, isNull);
      expect(sections[0].label, '未分類');
    });

    test('非連續但同肌群的項目不會被誤合併回同一區塊(照排序後的實際順序分組,不整體重排)', () {
      // 模擬輸入順序不是先照肌群排序好的極端情況(正常來說 repository
      // 已排序,不會發生,但函式本身不該假裝重排——這裡驗證它確實只做
      // 「連續收攏」,不是「先分組再排序」。
      final summaries = [
        _summary(exerciseId: 'e1', exerciseName: '深蹲', muscleGroup: PrimaryMuscleGroup.legs),
        _summary(exerciseId: 'e2', exerciseName: '臥推', muscleGroup: PrimaryMuscleGroup.chest),
        _summary(exerciseId: 'e3', exerciseName: '硬舉', muscleGroup: PrimaryMuscleGroup.legs),
      ];

      final sections = groupByMuscleGroup(summaries);

      expect(sections.length, 3);
      expect(sections.map((s) => s.muscleGroup).toList(), [
        PrimaryMuscleGroup.legs,
        PrimaryMuscleGroup.chest,
        PrimaryMuscleGroup.legs,
      ]);
    });

    test('空清單回傳空區塊清單', () {
      expect(groupByMuscleGroup(const []), isEmpty);
    });
  });
}
