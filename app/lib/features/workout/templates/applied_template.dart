// 「套用模板 -> 初始訓練資料」的純函式,對照 iOS
// `WorkoutViewModel.startWorkoutFromTemplate`:依模板底下每個動作的
// suggestedSets 產生對應數量的初始組,重量固定 0、次數採 suggestedReps。
//
// 刻意設計成不依賴 UI/資料庫的純資料轉換——輸入一個已經從 repository 讀出、
// 掛好 exercises 的 [WorkoutTemplate],輸出 [AppliedTemplate]。波 3 第二段
// (訓練核心流)會直接消費這個型別建立進行中訓練草稿,這裡先獨立測試好
// 轉換邏輯本身,不用等第二段的訓練流程落地。
//
// null 語意:suggestedSets 為 null 時視為「沒有建議組數」,產生 0 組(不是
// 預設 1 組)——維持函式本身「組數 = suggestedSets」這個單純、可預期的
// 對照關係,不夾帶額外假設;呼叫端(訓練核心流)如果想給使用者至少一組
// 可填,屬於那一層的 UX 決定,不在這個純函式的職責內。suggestedReps 為
// null 同理,對應到 0 次。
import '../../../data/models/workout_template.dart';

/// 單一組的初始資料。
class AppliedTemplateSet {
  final double weight;
  final int reps;

  const AppliedTemplateSet({required this.weight, required this.reps});

  @override
  bool operator ==(Object other) =>
      other is AppliedTemplateSet && other.weight == weight && other.reps == reps;

  @override
  int get hashCode => Object.hash(weight, reps);

  @override
  String toString() => 'AppliedTemplateSet(weight: $weight, reps: $reps)';
}

/// 單一動作的初始資料。
class AppliedTemplateExercise {
  final String exerciseId;
  final String exerciseName;
  final List<AppliedTemplateSet> sets;

  const AppliedTemplateExercise({
    required this.exerciseId,
    required this.exerciseName,
    required this.sets,
  });

  @override
  bool operator ==(Object other) =>
      other is AppliedTemplateExercise &&
      other.exerciseId == exerciseId &&
      other.exerciseName == exerciseName &&
      _listEquals(other.sets, sets);

  @override
  int get hashCode => Object.hash(exerciseId, exerciseName, Object.hashAll(sets));

  @override
  String toString() =>
      'AppliedTemplateExercise(exerciseId: $exerciseId, exerciseName: $exerciseName, sets: $sets)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 套用模板產生的初始訓練資料。
class AppliedTemplate {
  final String templateId;
  final String templateName;
  final List<AppliedTemplateExercise> exercises;

  const AppliedTemplate({
    required this.templateId,
    required this.templateName,
    required this.exercises,
  });
}

/// 套用模板 -> 初始訓練資料。[template.exercises] 必須已經掛好
/// [TemplateExercise.exercise](TemplateRepository 的 `_hydrate` 已如此
/// 保證)——找不到對應動作時,exerciseName 退回空字串,不拋錯(避免因為
/// 單一動作資料不完整而讓整個套用流程失敗)。
AppliedTemplate applyTemplate(WorkoutTemplate template) {
  return AppliedTemplate(
    templateId: template.id,
    templateName: template.name,
    exercises: [
      for (final templateExercise in template.exercises)
        AppliedTemplateExercise(
          exerciseId: templateExercise.exerciseId,
          exerciseName: templateExercise.exercise?.name ?? '',
          sets: List.generate(
            templateExercise.suggestedSets ?? 0,
            (_) => AppliedTemplateSet(weight: 0, reps: templateExercise.suggestedReps ?? 0),
          ),
        ),
    ],
  );
}
