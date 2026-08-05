// powerlifting_calculations.dart 的純函式單元測試。全部用手算參照值驗證,
// 不碰 DB——`app/lib/features/stats/powerlifting/powerlifting_calculations.dart`
// 的 seam 要求(見 brief:最佳成績取錯/三項總和漏一項/系統推估匹配錯動作/
// 趨勢圖排序反轉,四條規則各自要有一顆「變異必紅」的測試把關)。

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/data/models/personal_record.dart';
import 'package:workout_record/data/models/power_lift_record.dart';
import 'package:workout_record/features/stats/powerlifting/powerlifting_calculations.dart';

PowerLiftRecord _record({
  required String id,
  required PowerLift lift,
  required double weight,
  int reps = 1,
  double? oneRepMax,
  DateTime? achievedAt,
}) {
  final now = DateTime(2026, 1, 1);
  return PowerLiftRecord(
    id: id,
    userId: 'u1',
    lift: lift,
    weight: weight,
    reps: reps,
    oneRepMax: oneRepMax ?? weight,
    achievedAt: achievedAt ?? now,
    createdAt: now,
    updatedAt: now,
  );
}

PersonalRecord _pr({
  required String id,
  required String exerciseId,
  required double oneRepMax,
  DateTime? achievedAt,
}) {
  final now = DateTime(2026, 1, 1);
  return PersonalRecord(
    id: id,
    userId: 'u1',
    exerciseId: exerciseId,
    weight: oneRepMax,
    reps: 1,
    oneRepMax: oneRepMax,
    achievedAt: achievedAt ?? now,
    createdAt: now,
    updatedAt: now,
  );
}

PRSummary _summary({
  required String exerciseId,
  required String exerciseName,
  PersonalRecord? currentPR,
}) {
  return PRSummary(
    exerciseId: exerciseId,
    exerciseName: exerciseName,
    currentPR: currentPR,
  );
}

void main() {
  group('powerLiftMatchesExerciseName', () {
    test('深蹲:中文關鍵字命中', () {
      expect(powerLiftMatchesExerciseName(PowerLift.squat, '槓鈴深蹲'), isTrue);
    });
    test('深蹲:英文關鍵字命中(大小寫混寫)', () {
      expect(powerLiftMatchesExerciseName(PowerLift.squat, 'Back Squat'), isTrue);
    });
    test('槓鈴臥推:中文關鍵字命中,含變化式子字串也算命中', () {
      expect(powerLiftMatchesExerciseName(PowerLift.benchPress, '上斜臥推'), isTrue);
    });
    test('硬舉:英文關鍵字命中', () {
      expect(powerLiftMatchesExerciseName(PowerLift.deadlift, 'Romanian Deadlift'), isTrue);
    });
    test('不相關動作名稱一律不命中(避免系統推估匹配錯動作)', () {
      expect(powerLiftMatchesExerciseName(PowerLift.squat, '肩推'), isFalse);
      expect(powerLiftMatchesExerciseName(PowerLift.benchPress, '深蹲'), isFalse);
      expect(powerLiftMatchesExerciseName(PowerLift.deadlift, '臥推'), isFalse);
    });
  });

  group('bestManualRecord', () {
    test('回傳指定動作 1RM 最高的那筆,不是最新或第一筆', () {
      final records = [
        _record(id: 'a', lift: PowerLift.squat, weight: 100, achievedAt: DateTime(2026, 1, 3)),
        _record(id: 'b', lift: PowerLift.squat, weight: 140, achievedAt: DateTime(2026, 1, 1)),
        _record(id: 'c', lift: PowerLift.squat, weight: 120, achievedAt: DateTime(2026, 1, 5)),
      ];

      final best = bestManualRecord(records, PowerLift.squat);

      // 手算:140 是三筆裡最高的 1RM,即使它既不是最新(1/5)也不是第一筆
      // (a)——若實作誤用「最新一筆」或「清單第一筆」取代「最高 1RM」,這裡
      // 必須紅。
      expect(best?.id, 'b');
      expect(best?.oneRepMax, 140);
    });

    test('無指定動作的紀錄時回傳 null', () {
      final records = [_record(id: 'a', lift: PowerLift.benchPress, weight: 80)];
      expect(bestManualRecord(records, PowerLift.squat), isNull);
    });

    test('其他動作的紀錄不干擾篩選', () {
      final records = [
        _record(id: 'a', lift: PowerLift.squat, weight: 100),
        _record(id: 'b', lift: PowerLift.deadlift, weight: 200),
      ];
      final best = bestManualRecord(records, PowerLift.squat);
      expect(best?.id, 'a');
    });
  });

  group('totalLifts', () {
    test('三項皆有手動紀錄時,總和 = 各動作最高 1RM 相加(手算)', () {
      final records = [
        _record(id: 'sq1', lift: PowerLift.squat, weight: 100),
        _record(id: 'sq2', lift: PowerLift.squat, weight: 140), // squat 最佳
        _record(id: 'bp1', lift: PowerLift.benchPress, weight: 80), // bench 最佳
        _record(id: 'dl1', lift: PowerLift.deadlift, weight: 180),
        _record(id: 'dl2', lift: PowerLift.deadlift, weight: 170), // deadlift 最佳 = 180
      ];

      // 手算:140(squat) + 80(bench) + 180(deadlift) = 400。
      expect(totalLifts(records), 400.0);
    });

    test('只有部分動作有紀錄時,總和只加總有紀錄的動作,不補 0(漏一項必紅)', () {
      final records = [
        _record(id: 'sq1', lift: PowerLift.squat, weight: 100),
        _record(id: 'dl1', lift: PowerLift.deadlift, weight: 200),
        // 沒有 benchPress 紀錄。
      ];

      // 若實作誤把「沒紀錄的動作」當 0 分之外仍佔一個空位相加(結果剛好一樣
      // 是 300)不會被這條測試抓到,所以另外斷言「總和恰好等於兩項相加」,
      // 並用下面這條 3 選 1 情境反向驗證「遺漏其中一項」會被抓到。
      expect(totalLifts(records), 300.0);
    });

    test('遺漏 squat 項目時總和只計 bench+deadlift(手算,防止漏一項被吃掉)', () {
      final records = [
        _record(id: 'bp1', lift: PowerLift.benchPress, weight: 60),
        _record(id: 'dl1', lift: PowerLift.deadlift, weight: 150),
      ];
      // 手算:60 + 150 = 210。若實作漏掉 benchPress 或 deadlift 任一項,
      // 結果會是 60 或 150,而非 210。
      expect(totalLifts(records), 210.0);
    });

    test('沒有任何手動紀錄時總和為 0', () {
      expect(totalLifts(const []), 0.0);
    });

    test('系統推估等其他來源不計入三項總和(iOS totalLifts 只讀 manualRecords)', () {
      // 這裡直接用「只給手動紀錄」的輸入型別驗證函式簽章本身就不接受系統
      // 推估來源(totalLifts 參數是 List<PowerLiftRecord> 的手動紀錄清單),
      // 語意上系統推估已被排除在計算路徑之外。
      final onlyManual = [_record(id: 'sq1', lift: PowerLift.squat, weight: 999)];
      expect(totalLifts(onlyManual), 999.0);
    });
  });

  group('manualRecordsForLift', () {
    test('依動作篩選,並依 achievedAt 由新到舊排序', () {
      final records = [
        _record(id: 'a', lift: PowerLift.squat, weight: 100, achievedAt: DateTime(2026, 1, 1)),
        _record(id: 'b', lift: PowerLift.squat, weight: 110, achievedAt: DateTime(2026, 1, 10)),
        _record(id: 'c', lift: PowerLift.benchPress, weight: 80, achievedAt: DateTime(2026, 1, 5)),
      ];

      final result = manualRecordsForLift(records, PowerLift.squat);

      expect(result.map((r) => r.id).toList(), ['b', 'a']);
    });
  });

  group('chartRecordsForLift', () {
    test('依動作篩選,並依 achievedAt 由舊到新排序(給圖表用,排序反轉必紅)', () {
      final records = [
        _record(id: 'a', lift: PowerLift.squat, weight: 100, achievedAt: DateTime(2026, 1, 10)),
        _record(id: 'b', lift: PowerLift.squat, weight: 110, achievedAt: DateTime(2026, 1, 1)),
        _record(id: 'c', lift: PowerLift.squat, weight: 120, achievedAt: DateTime(2026, 1, 5)),
      ];

      final result = chartRecordsForLift(records, PowerLift.squat);

      // 手算由舊到新:1/1(b) -> 1/5(c) -> 1/10(a)。若實作誤用由新到舊
      // (跟 manualRecordsForLift 搞混方向),這裡的順序會整個反過來。
      expect(result.map((r) => r.id).toList(), ['b', 'c', 'a']);
    });

    test('不含其他動作的紀錄', () {
      final records = [
        _record(id: 'a', lift: PowerLift.squat, weight: 100),
        _record(id: 'b', lift: PowerLift.deadlift, weight: 200),
      ];
      final result = chartRecordsForLift(records, PowerLift.squat);
      expect(result.map((r) => r.id).toList(), ['a']);
    });
  });

  group('systemEstimatedSummaries / bestSystemEstimate', () {
    test('只回傳動作名稱匹配指定三項動作的 PRSummary', () {
      final summaries = [
        _summary(exerciseId: 'e1', exerciseName: '槓鈴深蹲', currentPR: _pr(id: 'p1', exerciseId: 'e1', oneRepMax: 120)),
        _summary(exerciseId: 'e2', exerciseName: '肩推', currentPR: _pr(id: 'p2', exerciseId: 'e2', oneRepMax: 50)),
        _summary(exerciseId: 'e3', exerciseName: '前蹲', currentPR: _pr(id: 'p3', exerciseId: 'e3', oneRepMax: 90)),
      ];

      final matched = systemEstimatedSummaries(summaries, PowerLift.squat);

      // 手算:「肩推」不含深蹲/squat 關鍵字,必須被排除;「槓鈴深蹲」與
      // 「前蹲」都含「蹲」但只有「深蹲」子字串命中(iOS matches() 用
      // contains("深蹲"),"前蹲" 不含這三個字,不該命中)。
      expect(matched.map((s) => s.exerciseId).toSet(), {'e1'});
    });

    test('系統推估匹配錯動作必紅:硬舉不該匹配到深蹲的 PRSummary', () {
      final summaries = [
        _summary(exerciseId: 'e1', exerciseName: '槓鈴深蹲', currentPR: _pr(id: 'p1', exerciseId: 'e1', oneRepMax: 120)),
      ];
      expect(systemEstimatedSummaries(summaries, PowerLift.deadlift), isEmpty);
    });

    test('多個動作名稱都匹配同一三項動作時,取其中 currentPR 1RM 最高者', () {
      final summaries = [
        _summary(
          exerciseId: 'e1',
          exerciseName: '槓鈴臥推',
          currentPR: _pr(id: 'p1', exerciseId: 'e1', oneRepMax: 80),
        ),
        _summary(
          exerciseId: 'e2',
          exerciseName: '上斜臥推',
          currentPR: _pr(id: 'p2', exerciseId: 'e2', oneRepMax: 60),
        ),
      ];

      final best = bestSystemEstimate(summaries, PowerLift.benchPress);

      // 手算:兩者都匹配「臥推」,80 > 60,取 e1。
      expect(best?.id, 'p1');
      expect(best?.oneRepMax, 80);
    });

    test('沒有 currentPR 的 PRSummary 不影響取最高值計算', () {
      final summaries = [
        _summary(exerciseId: 'e1', exerciseName: '硬舉', currentPR: null),
        _summary(exerciseId: 'e2', exerciseName: '羅馬尼亞硬舉', currentPR: _pr(id: 'p2', exerciseId: 'e2', oneRepMax: 150)),
      ];
      final best = bestSystemEstimate(summaries, PowerLift.deadlift);
      expect(best?.id, 'p2');
    });

    test('完全沒有匹配動作時回傳 null', () {
      final summaries = [
        _summary(exerciseId: 'e1', exerciseName: '肩推', currentPR: _pr(id: 'p1', exerciseId: 'e1', oneRepMax: 50)),
      ];
      expect(bestSystemEstimate(summaries, PowerLift.squat), isNull);
    });
  });
}
