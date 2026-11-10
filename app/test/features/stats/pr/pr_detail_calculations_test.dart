// PR 詳情頁純函式層:當前 PR 挑選、排序、進步統計、公式重算。
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_record/data/models/personal_record.dart';
import 'package:workout_record/features/settings/preferences/one_rm_formula_preference.dart';
import 'package:workout_record/features/stats/pr/pr_detail_calculations.dart';

PersonalRecord _pr(
  String id, {
  double weight = 100,
  int reps = 1,
  double? oneRepMax,
  required DateTime achievedAt,
}) {
  final now = DateTime(2026, 1, 1);
  return PersonalRecord(
    id: id,
    userId: 'u',
    exerciseId: 'e',
    weight: weight,
    reps: reps,
    oneRepMax: oneRepMax ?? weight,
    achievedAt: achievedAt,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('空資料:isEmpty、current 與 progress 皆為空', () {
    final data = buildPrDetailData(const [], OneRmFormula.epley);
    expect(data.isEmpty, isTrue);
    expect(data.current, isNull);
    expect(data.progress, isNull);
  });

  test('歷史新到舊、圖表舊到新,與輸入順序無關', () {
    final data = buildPrDetailData([
      _pr('mid', achievedAt: DateTime(2026, 2, 1)),
      _pr('new', achievedAt: DateTime(2026, 3, 1)),
      _pr('old', achievedAt: DateTime(2026, 1, 1)),
    ], OneRmFormula.epley);
    expect(data.historyDesc.map((e) => e.record.id), ['new', 'mid', 'old']);
    expect(data.chartAsc.map((e) => e.record.id), ['old', 'mid', 'new']);
  });

  test('當前 PR 是 1RM 最高的一筆,不是最新一筆', () {
    final data = buildPrDetailData([
      _pr('best', weight: 140, achievedAt: DateTime(2026, 1, 1)),
      _pr('latest', weight: 100, achievedAt: DateTime(2026, 3, 1)),
    ], OneRmFormula.epley);
    expect(data.current!.record.id, 'best');
  });

  test('1RM 同值時當前 PR 取達成日較新的一筆', () {
    final data = buildPrDetailData([
      _pr('older', weight: 100, achievedAt: DateTime(2026, 1, 1)),
      _pr('newer', weight: 100, achievedAt: DateTime(2026, 2, 1)),
    ], OneRmFormula.epley);
    expect(data.current!.record.id, 'newer');
  });

  test('1RM 依偏好公式重算(忽略儲存的 oneRepMax):100kg x 10', () {
    final records = [_pr('a', weight: 100, reps: 10, oneRepMax: 1, achievedAt: DateTime(2026, 1, 1))];
    // Epley 100*(1+10/30)=133.333;Brzycki 100*36/27=133.333;
    // Lander 100*100/(101.3-26.7123)=134.0...
    expect(buildPrDetailData(records, OneRmFormula.epley).current!.oneRepMax, closeTo(133.3333, 1e-3));
    expect(buildPrDetailData(records, OneRmFormula.brzycki).current!.oneRepMax, closeTo(133.3333, 1e-3));
    expect(buildPrDetailData(records, OneRmFormula.lander).current!.oneRepMax, closeTo(134.0, 0.1));
  });

  test('1 次時 1RM 等於重量', () {
    final data = buildPrDetailData(
      [_pr('a', weight: 142.5, reps: 1, achievedAt: DateTime(2026, 1, 1))],
      OneRmFormula.brzycki,
    );
    expect(data.current!.oneRepMax, 142.5);
  });

  test('進步統計:最新一筆減最早一筆,單筆為 null', () {
    final two = buildPrDetailData([
      _pr('a', weight: 100, achievedAt: DateTime(2026, 1, 1)),
      _pr('b', weight: 125, achievedAt: DateTime(2026, 2, 1)),
    ], OneRmFormula.epley);
    expect(two.progress!.deltaKg, 25);
    expect(two.progress!.percent, 25);

    final one = buildPrDetailData([_pr('a', achievedAt: DateTime(2026, 1, 1))], OneRmFormula.epley);
    expect(one.progress, isNull);
  });
}
