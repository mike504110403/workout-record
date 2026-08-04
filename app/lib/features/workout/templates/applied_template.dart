// 「套用模板 -> 初始訓練資料」的純函式。
//
// **出處更正(code-M1)**:iOS 有兩支同名的 `startWorkoutFromTemplate`——
// `ViewModels/WorkoutViewModel.swift:54-70` 那支只是把動作名稱/id 轉成
// `WorkoutExerciseViewModel(..., sets: [])`,完全不展開初始組;真正「依
// suggestedSets 展開出對應數量初始組」的是
// `Views/Workout/EnhancedWorkoutFlowView.swift:579-609` 的同名函式——
// 依模板底下每個動作,產生 `suggestedSets ?? 3` 組、重量固定 0、
// 次數採 `suggestedReps ?? 10`(見該檔案 584/589 行)。這裡對照的是
// EnhancedWorkoutFlowView 版本(它是實際掛在畫面上的訓練流程),不是
// WorkoutViewModel 那支——先前版本的註解誤指到 WorkoutViewModel,已修正。
//
// 刻意設計成不依賴 UI/資料庫的純資料轉換——輸入一個已經從 repository 讀出、
// 掛好 exercises 的 [WorkoutTemplate],輸出 [AppliedTemplate]。波 3 第二段
// (訓練核心流)會直接消費這個型別建立進行中訓練草稿,這裡先獨立測試好
// 轉換邏輯本身,不用等第二段的訓練流程落地。
//
// **null 預設值(code-M2,已裁:對齊 iOS)**:suggestedSets/suggestedReps 為
// null 時分別預設 3 組 / 10 次,對齊 EnhancedWorkoutFlowView 的
// `?? 3` / `?? 10`(見上)。先前版本用 `?? 0`(null 產生 0 組)是與 iOS
// 相反的選擇,已改正。建立/編輯表單(template_form_page.dart)本身仍然
// 讓使用者自由留空 suggestedSets/suggestedReps——只有「套用模板展開初始
// 組」這一步才套用 3/10 這組預設值,對齊 iOS 語意。
import 'package:flutter/foundation.dart' show listEquals;

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
      listEquals(other.sets, sets);

  @override
  int get hashCode => Object.hash(exerciseId, exerciseName, Object.hashAll(sets));

  @override
  String toString() =>
      'AppliedTemplateExercise(exerciseId: $exerciseId, exerciseName: $exerciseName, sets: $sets)';
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

  // minor 補件:另外兩個子型別(AppliedTemplateSet/AppliedTemplateExercise)
  // 都有 ==/hashCode,這裡先前沒有,不一致——補齊讓整組型別一致可比較
  // (波 3 第二段訓練核心流的測試會需要拿 AppliedTemplate 做值比對)。
  @override
  bool operator ==(Object other) =>
      other is AppliedTemplate &&
      other.templateId == templateId &&
      other.templateName == templateName &&
      listEquals(other.exercises, exercises);

  @override
  int get hashCode => Object.hash(templateId, templateName, Object.hashAll(exercises));

  @override
  String toString() =>
      'AppliedTemplate(templateId: $templateId, templateName: $templateName, exercises: $exercises)';
}

/// 套用模板 -> 初始訓練資料。[template.exercises] 必須已經掛好
/// [TemplateExercise.exercise](TemplateRepository 的 `_hydrate` 已如此
/// 保證)——找不到對應動作時,exerciseName 退回空字串,不拋錯(避免因為
/// 單一動作資料不完整而讓整個套用流程失敗)。
///
/// suggestedSets/suggestedReps 為 null 時分別預設 3 組 / 10 次,對齊 iOS
/// `EnhancedWorkoutFlowView.startWorkoutFromTemplate` 的 `?? 3` / `?? 10`
/// (見檔案開頭出處說明)。
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
            templateExercise.suggestedSets ?? 3,
            (_) => AppliedTemplateSet(weight: 0, reps: templateExercise.suggestedReps ?? 10),
          ),
        ),
    ],
  );
}
