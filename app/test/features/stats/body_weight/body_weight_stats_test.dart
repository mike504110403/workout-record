// 純函式測試：computeBodyWeightSummary / sortBodyWeightsAscending。參照值
// 全部手算（不是重複被測程式的算法），依 /tdd 的紀律——這兩個函式是
// widget test 沒辦法窮舉覆蓋的邊界（空清單、一筆、多筆）的唯一防線。
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/data/models/body_weight.dart';
import 'package:workout_record/features/stats/body_weight/body_weight_stats.dart';

BodyWeight _entry({required String id, required double weight, required DateTime measuredAt}) {
  final now = DateTime(2026, 1, 1);
  return BodyWeight(
    id: id,
    userId: 'user-1',
    weight: weight,
    measuredAt: measuredAt,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('computeBodyWeightSummary', () {
    test('空清單:current/average/max/min/change 皆為 null,target 仍照傳入值回傳', () {
      final summary = computeBodyWeightSummary(const [], targetWeight: 65.0);

      expect(summary.current, isNull);
      expect(summary.average, isNull);
      expect(summary.max, isNull);
      expect(summary.min, isNull);
      expect(summary.change, isNull);
      expect(summary.target, 65.0);
    });

    test('空清單且無目標:全部欄位皆為 null', () {
      final summary = computeBodyWeightSummary(const []);

      expect(summary.current, isNull);
      expect(summary.target, isNull);
    });

    test('一筆紀錄:current=average=max=min=該筆體重,change 為 null(沒有次新可比)', () {
      final entries = [_entry(id: 'a', weight: 70.0, measuredAt: DateTime(2026, 1, 10))];

      final summary = computeBodyWeightSummary(entries, targetWeight: 68.0);

      expect(summary.current, 70.0);
      expect(summary.average, 70.0);
      expect(summary.max, 70.0);
      expect(summary.min, 70.0);
      expect(summary.change, isNull);
      expect(summary.target, 68.0);
    });

    // 手算參照值:輸入(新到舊)80.0, 76.0, 78.0, 74.0
    // current = 80.0 ([0])
    // average = (80.0+76.0+78.0+74.0)/4 = 308.0/4 = 77.0
    // max = 80.0, min = 74.0
    // change = 80.0 - 76.0 = 4.0(取 [0]-[1],不是排序後首尾相減)
    test('多筆紀錄(新到舊排序輸入):平均/最高/最低/變化幅度依手算參照值', () {
      final entries = [
        _entry(id: 'newest', weight: 80.0, measuredAt: DateTime(2026, 1, 20)),
        _entry(id: 'second', weight: 76.0, measuredAt: DateTime(2026, 1, 15)),
        _entry(id: 'third', weight: 78.0, measuredAt: DateTime(2026, 1, 10)),
        _entry(id: 'oldest', weight: 74.0, measuredAt: DateTime(2026, 1, 1)),
      ];

      final summary = computeBodyWeightSummary(entries, targetWeight: 70.0);

      expect(summary.current, 80.0);
      expect(summary.average, 77.0);
      expect(summary.max, 80.0);
      expect(summary.min, 74.0);
      // 變化幅度必須是 [0]-[1] = 80.0-76.0 = 4.0,不是 max-min(6.0)、不是
      // 首尾相減(80.0-74.0=6.0)之類「取錯兩筆」的誤算——這條斷言就是在
      // 守住這個變異。
      expect(summary.change, 4.0);
      expect(summary.target, 70.0);
    });

    test('變化幅度可為負值(體重下降):最新 71.0 減次新 75.0 = -4.0', () {
      final entries = [
        _entry(id: 'newest', weight: 71.0, measuredAt: DateTime(2026, 1, 20)),
        _entry(id: 'second', weight: 75.0, measuredAt: DateTime(2026, 1, 10)),
      ];

      final summary = computeBodyWeightSummary(entries);

      expect(summary.change, -4.0);
    });
  });

  group('computeBodyWeightSummary:距目標 / 30 天變化', () {
    // 手算:最新 2026-02-01=79.0;1/20(12 天前)=80.0;1/10(22 天前)=82.0;
    // 12/1(62 天前,窗口外)=90.0。窗口內最早一筆 = 1/10 的 82.0。
    final entriesDesc = [
      _entry(id: 'e0', weight: 79.0, measuredAt: DateTime(2026, 2, 1)),
      _entry(id: 'e1', weight: 80.0, measuredAt: DateTime(2026, 1, 20)),
      _entry(id: 'e2', weight: 82.0, measuredAt: DateTime(2026, 1, 10)),
      _entry(id: 'e3', weight: 90.0, measuredAt: DateTime(2025, 12, 1)),
    ];

    test('距目標 = 當前 - 目標(帶號);30 天變化 = 最新 - 窗口內最早', () {
      final summary = computeBodyWeightSummary(entriesDesc, targetWeight: 75.0);

      expect(summary.toTarget, closeTo(4.0, 1e-9));
      expect(summary.change30d, closeTo(-3.0, 1e-9));
    });

    test('已低於目標時距目標為負值', () {
      final summary = computeBodyWeightSummary(entriesDesc, targetWeight: 80.0);
      expect(summary.toTarget, closeTo(-1.0, 1e-9));
    });

    test('沒設目標 → toTarget 為 null;空清單兩者皆 null', () {
      expect(computeBodyWeightSummary(entriesDesc).toTarget, isNull);
      final empty = computeBodyWeightSummary(const [], targetWeight: 70.0);
      expect(empty.toTarget, isNull);
      expect(empty.change30d, isNull);
    });

    test('窗口內只有最新一筆(其餘都超過 30 天)→ change30d 為 null', () {
      final summary = computeBodyWeightSummary([
        _entry(id: 'n', weight: 80.0, measuredAt: DateTime(2026, 2, 1)),
        _entry(id: 'o', weight: 90.0, measuredAt: DateTime(2025, 12, 1)),
      ]);
      expect(summary.change30d, isNull);
    });

    test('剛好 30 天前的一筆算在窗口內(邊界含)', () {
      final summary = computeBodyWeightSummary([
        _entry(id: 'n', weight: 80.0, measuredAt: DateTime(2026, 2, 1)),
        _entry(id: 'b', weight: 85.0, measuredAt: DateTime(2026, 1, 2)),
      ]);
      expect(summary.change30d, closeTo(-5.0, 1e-9));
    });
  });

  group('sortBodyWeightsAscending', () {
    test('輸入新到舊,輸出反轉成舊到新', () {
      final entries = [
        _entry(id: 'newest', weight: 80.0, measuredAt: DateTime(2026, 1, 20)),
        _entry(id: 'middle', weight: 78.0, measuredAt: DateTime(2026, 1, 10)),
        _entry(id: 'oldest', weight: 74.0, measuredAt: DateTime(2026, 1, 1)),
      ];

      final ascending = sortBodyWeightsAscending(entries);

      expect(ascending.map((e) => e.id).toList(), ['oldest', 'middle', 'newest']);
    });

    test('不修改原始 list(回傳新的 list 副本)', () {
      final entries = [
        _entry(id: 'newest', weight: 80.0, measuredAt: DateTime(2026, 1, 20)),
        _entry(id: 'oldest', weight: 74.0, measuredAt: DateTime(2026, 1, 1)),
      ];
      final originalOrder = entries.map((e) => e.id).toList();

      sortBodyWeightsAscending(entries);

      expect(entries.map((e) => e.id).toList(), originalOrder);
    });

    test('空清單回傳空清單', () {
      expect(sortBodyWeightsAscending(const []), isEmpty);
    });
  });
}
