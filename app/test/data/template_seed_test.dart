// 系統模板種子測試(波 3 第一段,見
// .claude/decisions/2026-08-04-波3訓練流草稿寫穿與系統模板.md)。
//
// 驗證 seedIfEmpty()(app_database.dart)種進 Templates + TemplateExercises
// 的內容,跟 iOS WorkoutTemplateViewModel.swift:160-227 的 DEBUG mock 資料
// 一致。參照值是這裡手動抄錄自 iOS 原始碼的常數,刻意不從 seed_data.dart
// 匯入或依它算出來——避免「測試只是把被測程式碼的假設複製一遍」這種假
// 防護(獨立於被測物,才守得住)。
//
// 「上肢訓練」「全身訓練」的「臥推」「划船」「二頭彎舉」是 iOS mock 的
// 通用泛稱,不在 66 筆種子動作的精確名單裡,seed_data.dart 對應到各自最
// 通用的槓鈴變化版本並在檔案開頭申報——這裡的參照值同樣採對應後的名稱,
// 因為這是本次實作刻意做的資料轉換,不是要被這個測試抓出來的 bug。
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// 手抄自 iOS WorkoutTemplateViewModel.swift:160-227 —— 模板名稱 -> 動作
/// 名稱清單(依 orderIndex 順序)。
const Map<String, List<String>> kExpectedSystemTemplateExercises = {
  'PPL - Push (推)': ['槓鈴臥推', '上斜啞鈴臥推', '肩推', '側平舉', '三頭下壓'],
  'PPL - Pull (拉)': ['硬舉', '引體向上', '槓鈴划船', '坐姿划船', '槓鈴彎舉'],
  'PPL - Legs (腿)': ['深蹲', '羅馬尼亞硬舉', '腿推機', '腿彎舉', '提踵'],
  '上肢訓練': ['槓鈴臥推', '槓鈴划船', '肩推', '槓鈴彎舉', '三頭下壓'],
  '全身訓練': ['深蹲', '槓鈴臥推', '硬舉', '引體向上', '肩推'],
};

void main() {
  test('新開 DB 恰有 5 筆 isSystem 模板,userId 皆為 null,名稱對照 iOS mock', () async {
    final db = openTestDatabase();
    addTearDown(db.close);

    final systemTemplates =
        await (db.select(db.templates)..where((t) => t.isSystem.equals(true))).get();

    expect(systemTemplates, hasLength(5));
    expect(systemTemplates.every((t) => t.userId == null), isTrue);
    expect(
      systemTemplates.map((t) => t.name).toSet(),
      kExpectedSystemTemplateExercises.keys.toSet(),
    );
  });

  test('每個系統模板的 TemplateExercises 動作數與名稱依 orderIndex 對照 iOS mock', () async {
    final db = openTestDatabase();
    addTearDown(db.close);

    final systemTemplates =
        await (db.select(db.templates)..where((t) => t.isSystem.equals(true))).get();

    // minor 補件:先鎖住筆數——沒有這行,如果種子完全沒跑(systemTemplates
    // 是空清單),下面的 for 迴圈零次迭代照樣「通過」,是這批測試裡唯一一條
    // M2(略過整批種子)這種變異測不出來的,補上讓它變回會紅。
    expect(systemTemplates, hasLength(5));

    for (final template in systemTemplates) {
      final expectedNames = kExpectedSystemTemplateExercises[template.name];
      expect(expectedNames, isNotNull, reason: '未預期的系統模板名稱:${template.name}');

      final rows = await (db.select(db.templateExercises)
            ..where((t) => t.templateId.equals(template.id))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();

      expect(rows, hasLength(expectedNames!.length), reason: '模板「${template.name}」動作數不符');

      for (var i = 0; i < rows.length; i++) {
        final exercise =
            await (db.select(db.exercises)..where((t) => t.id.equals(rows[i].exerciseId)))
                .getSingle();
        expect(exercise.name, expectedNames[i], reason: '模板「${template.name}」第 $i 個動作名稱不符');
      }
    }
  });

  test('關聯完整性:每個系統模板動作的 exerciseId 都真實存在於 Exercises(JOIN 驗證,防名稱對應錯字)', () async {
    final db = openTestDatabase();
    addTearDown(db.close);

    final exerciseIds = (await db.select(db.exercises).get()).map((e) => e.id).toSet();
    final systemTemplateIds =
        (await (db.select(db.templates)..where((t) => t.isSystem.equals(true))).get())
            .map((t) => t.id)
            .toSet();
    final templateExercises = await db.select(db.templateExercises).get();
    final systemTemplateExercises =
        templateExercises.where((te) => systemTemplateIds.contains(te.templateId)).toList();

    // 5 個模板 x 5 個動作 = 25 筆,順便鎖住總數(對照 iOS mock 每個模板都
    // 恰好 5 個動作)。
    expect(systemTemplateExercises, hasLength(25));
    for (final te in systemTemplateExercises) {
      expect(
        exerciseIds.contains(te.exerciseId),
        isTrue,
        reason: 'templateExercise ${te.id} 的 exerciseId ${te.exerciseId} 不存在於 Exercises',
      );
    }
  });

  test('PPL - Push 的 suggestedSets/suggestedReps 逐一對照 iOS mock', () async {
    final db = openTestDatabase();
    addTearDown(db.close);

    final pushTemplate =
        await (db.select(db.templates)..where((t) => t.name.equals('PPL - Push (推)')))
            .getSingle();
    final rows = await (db.select(db.templateExercises)
          ..where((t) => t.templateId.equals(pushTemplate.id))
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();

    // 手算參照值,對照 WorkoutTemplateViewModel.swift:167-171
    // (槓鈴臥推 4x8、上斜啞鈴臥推 4x10、肩推 4x10、側平舉 3x12、三頭下壓 3x12)。
    expect(rows.map((r) => (r.suggestedSets, r.suggestedReps)).toList(), [
      (4, 8),
      (4, 10),
      (4, 10),
      (3, 12),
      (3, 12),
    ]);
  });

  test('種子是冪等的:重複呼叫 seedIfEmpty() 不會重複插入系統模板', () async {
    final db = openTestDatabase();
    addTearDown(db.close);

    await db.seedIfEmpty();
    await db.seedIfEmpty();

    final systemTemplates =
        await (db.select(db.templates)..where((t) => t.isSystem.equals(true))).get();
    expect(systemTemplates, hasLength(5));
  });
}
