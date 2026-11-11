// 記組 sheet(add_set_sheet.dart)的 widget 測試:大字輸入 + 兩側 −/+ stepper
// (重量步進依單位 kg 2.5 / lb 5、次數步進 1)、「進階選項」預設收合、
// 預填同動作上一組的重量/次數、儲存回傳契約(重量一律 kg)。
// 不需要 DB:只 override weightUnitProvider。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_record/features/settings/preferences/weight_unit.dart';
import 'package:workout_record/features/workout/add_set_sheet.dart';

typedef _Result = ({AddSetResult? value, bool done});

/// 開 sheet;回傳可讀取結果的 getter(sheet 關閉後才 done)。
Future<_Result Function()> _openSheet(
  WidgetTester tester, {
  WeightUnit unit = WeightUnit.kg,
  double? previousWeight,
  int? previousReps,
  double? initialWeight,
  int? initialReps,
  double? initialRpe,
  bool initialIsWarmup = false,
}) async {
  AddSetResult? value;
  var done = false;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [weightUnitProvider.overrideWithValue(unit)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                value = await showAddSetSheet(
                  context,
                  exerciseName: '深蹲',
                  setNumber: 2,
                  previousWeight: previousWeight,
                  previousReps: previousReps,
                  initialWeight: initialWeight,
                  initialReps: initialReps,
                  initialRpe: initialRpe,
                  initialIsWarmup: initialIsWarmup,
                );
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => (value: value, done: done);
}

String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

Future<void> _tap(WidgetTester tester, String key, [int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
  }
}

void main() {
  group('進階選項收合', () {
    testWidgets('新增組:RPE/暖身/休息/自動計時預設收合不渲染;展開後四項都在', (tester) async {
      await _openSheet(tester);

      expect(find.byKey(const Key('addSetWeightField')), findsOneWidget);
      expect(find.byKey(const Key('addSetRepsField')), findsOneWidget);
      expect(find.text('進階選項'), findsOneWidget);
      expect(find.byKey(const Key('addSetRpeField')), findsNothing);
      expect(find.byKey(const Key('addSetWarmupSwitch')), findsNothing);
      expect(find.byKey(const Key('addSetRestSecondsValue')), findsNothing);
      expect(find.byKey(const Key('addSetAutoStartRestTimerSwitch')), findsNothing);

      await tester.tap(find.text('進階選項'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('addSetRpeField')), findsOneWidget);
      expect(find.byKey(const Key('addSetWarmupSwitch')), findsOneWidget);
      expect(find.byKey(const Key('addSetRestSecondsValue')), findsOneWidget);
      expect(find.byKey(const Key('addSetAutoStartRestTimerSwitch')), findsOneWidget);
    });

    testWidgets('編輯帶有暖身/RPE 的既有組:預設展開以免已設定的值被藏起來', (tester) async {
      await _openSheet(tester, initialWeight: 40, initialReps: 10, initialIsWarmup: true);
      expect(find.byKey(const Key('addSetWarmupSwitch')), findsOneWidget);
    });

    testWidgets('編輯沒有暖身/RPE 的既有組:仍然收合', (tester) async {
      await _openSheet(tester, initialWeight: 40, initialReps: 10);
      expect(find.byKey(const Key('addSetWarmupSwitch')), findsNothing);
    });
  });

  group('重量 stepper', () {
    testWidgets('kg:每次 ±2.5;空白視為 0;下限 0', (tester) async {
      await _openSheet(tester);

      await _tap(tester, 'addSetWeightPlusButton');
      expect(_text(tester, 'addSetWeightField'), '2.5');
      await _tap(tester, 'addSetWeightPlusButton');
      expect(_text(tester, 'addSetWeightField'), '5');
      await _tap(tester, 'addSetWeightMinusButton', 5);
      expect(_text(tester, 'addSetWeightField'), '0');
    });

    testWidgets('lb:每次 ±5', (tester) async {
      await _openSheet(tester, unit: WeightUnit.lb);

      expect(find.text('重量 (lb)'), findsOneWidget);
      await _tap(tester, 'addSetWeightPlusButton', 2);
      expect(_text(tester, 'addSetWeightField'), '10');
      await _tap(tester, 'addSetWeightMinusButton');
      expect(_text(tester, 'addSetWeightField'), '5');
    });

    testWidgets('從手動輸入的值繼續步進,不產生浮點尾數', (tester) async {
      await _openSheet(tester);

      await tester.enterText(find.byKey(const Key('addSetWeightField')), '101.3');
      await tester.pump();
      await _tap(tester, 'addSetWeightPlusButton');
      expect(_text(tester, 'addSetWeightField'), '103.8');
    });

    testWidgets('步進單位純函式:kg 2.5 / lb 5', (tester) async {
      expect(addSetWeightStep(WeightUnit.kg), 2.5);
      expect(addSetWeightStep(WeightUnit.lb), 5);
    });
  });

  group('次數 stepper', () {
    testWidgets('每次 ±1;空白視為 0;下限 0', (tester) async {
      await _openSheet(tester);

      await _tap(tester, 'addSetRepsPlusButton', 2);
      expect(_text(tester, 'addSetRepsField'), '2');
      await _tap(tester, 'addSetRepsMinusButton');
      expect(_text(tester, 'addSetRepsField'), '1');
      await _tap(tester, 'addSetRepsMinusButton', 3);
      expect(_text(tester, 'addSetRepsField'), '0');
    });
  });

  group('預填與儲存', () {
    testWidgets('新增組:預填同動作上一組的重量/次數,可直接接著 stepper 調整後儲存', (tester) async {
      final result = await _openSheet(tester, previousWeight: 60, previousReps: 8);

      expect(_text(tester, 'addSetWeightField'), '60');
      expect(_text(tester, 'addSetRepsField'), '8');

      await _tap(tester, 'addSetWeightPlusButton');
      await _tap(tester, 'addSetRepsPlusButton');
      await tester.tap(find.byKey(const Key('addSetSaveButton')));
      await tester.pumpAndSettle();

      final r = result();
      expect(r.done, isTrue);
      expect(r.value!.weight, 62.5);
      expect(r.value!.reps, 9);
      expect(r.value!.isWarmup, isFalse);
      expect(r.value!.autoStartRestTimer, isTrue);
    });

    testWidgets('沒有上一組:欄位空白,儲存鈕停用;stepper 補上數值後才可儲存', (tester) async {
      await _openSheet(tester);

      FilledButton save() => tester.widget<FilledButton>(find.byKey(const Key('addSetSaveButton')));
      expect(save().onPressed, isNull);

      await _tap(tester, 'addSetWeightPlusButton');
      expect(save().onPressed, isNull); // 只有重量,次數仍空白
      await _tap(tester, 'addSetRepsPlusButton');
      expect(save().onPressed, isNotNull);
    });

    testWidgets('lb 模式:stepper 的顯示值存回 kg(儲存值恆 kg)', (tester) async {
      final result = await _openSheet(tester, unit: WeightUnit.lb);

      await _tap(tester, 'addSetWeightPlusButton', 4); // 20 lb
      await _tap(tester, 'addSetRepsPlusButton');
      await tester.tap(find.byKey(const Key('addSetSaveButton')));
      await tester.pumpAndSettle();

      expect(result().value!.weight, closeTo(displayToKg(20, WeightUnit.lb), 0.001));
    });

    testWidgets('取消:回傳 null', (tester) async {
      final result = await _openSheet(tester, previousWeight: 60, previousReps: 8);
      await tester.tap(find.byKey(const Key('addSetCancelButton')));
      await tester.pumpAndSettle();
      expect(result().done, isTrue);
      expect(result().value, isNull);
    });
  });

  // ui-polish:進行中訓練頁才開的 compact 版面與「存並再記一組」(預設關閉,
  // 歷史編輯頁維持舊版面——上面幾組測試就是舊版面的守門)。
  group('compact 版面 + 存並再記一組(進行中訓練頁)', () {
    Future<({List<AddSetResult> saved, AddSetResult? Function() popped})> openCompact(
      WidgetTester tester, {
      bool saveOk = true,
      bool withContinue = true,
    }) async {
      final saved = <AddSetResult>[];
      AddSetResult? popped;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [weightUnitProvider.overrideWithValue(WeightUnit.kg)],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    popped = await showAddSetSheet(
                      context,
                      exerciseName: '深蹲',
                      setNumber: 2,
                      previousWeight: 60,
                      previousReps: 8,
                      compact: true,
                      onSaveAndContinue: withContinue
                          ? (result) async {
                              if (saveOk) saved.add(result);
                              return saveOk;
                            }
                          : null,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return (saved: saved, popped: () => popped);
    }

    testWidgets('動作名與「第 N 組」同一行;沒有取消鈕;進階選項是一行小入口', (tester) async {
      await openCompact(tester);

      final nameY = tester.getCenter(find.text('深蹲')).dy;
      final numberY = tester.getCenter(find.byKey(const Key('addSetSetNumberText'))).dy;
      expect((nameY - numberY).abs(), lessThan(4));
      expect(find.byKey(const Key('addSetCancelButton')), findsNothing);
      expect(find.byKey(const Key('addSetAdvancedTile')), findsNothing);
      expect(find.byKey(const Key('addSetRpeField')), findsNothing);

      await tester.tap(find.byKey(const Key('addSetAdvancedToggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('addSetRpeField')), findsOneWidget);
      expect(find.byKey(const Key('addSetWarmupSwitch')), findsOneWidget);
    });

    testWidgets('存並再記一組:寫入這組、sheet 不關、組號 +1、數字保留;再按一次記第二組', (tester) async {
      final h = await openCompact(tester);
      expect(find.text('第 2 組'), findsOneWidget);

      await tester.tap(find.byKey(const Key('addSetSaveAndContinueButton')));
      await tester.pumpAndSettle();

      expect(h.saved, hasLength(1));
      expect((h.saved.single.weight, h.saved.single.reps), (60.0, 8));
      expect(find.byKey(const Key('addSetSaveButton')), findsOneWidget, reason: 'sheet 還開著');
      expect(find.text('第 3 組'), findsOneWidget);
      expect(_text(tester, 'addSetWeightField'), '60');
      expect(_text(tester, 'addSetRepsField'), '8');

      await tester.enterText(find.byKey(const Key('addSetRepsField')), '6');
      await tester.tap(find.byKey(const Key('addSetSaveAndContinueButton')));
      await tester.pumpAndSettle();
      expect(h.saved.map((r) => r.reps), [8, 6]);
      expect(find.text('第 4 組'), findsOneWidget);
    });

    testWidgets('存並再記一組寫入失敗:組號不變、sheet 不關', (tester) async {
      final h = await openCompact(tester, saveOk: false);

      await tester.tap(find.byKey(const Key('addSetSaveAndContinueButton')));
      await tester.pumpAndSettle();

      expect(h.saved, isEmpty);
      expect(find.text('第 2 組'), findsOneWidget);
      expect(find.byKey(const Key('addSetSaveButton')), findsOneWidget);
    });

    testWidgets('儲存:回傳結果並關閉;沒帶 onSaveAndContinue 時不顯示該鈕', (tester) async {
      final h = await openCompact(tester, withContinue: false);
      expect(find.byKey(const Key('addSetSaveAndContinueButton')), findsNothing);

      await tester.tap(find.byKey(const Key('addSetSaveButton')));
      await tester.pumpAndSettle();

      expect(h.popped()?.weight, 60);
      expect(find.byKey(const Key('addSetSaveButton')), findsNothing);
    });

    testWidgets('舊版面(預設)仍有取消鈕、沒有「存並再記一組」', (tester) async {
      await _openSheet(tester, previousWeight: 60, previousReps: 8);
      expect(find.byKey(const Key('addSetCancelButton')), findsOneWidget);
      expect(find.byKey(const Key('addSetSaveAndContinueButton')), findsNothing);
      expect(find.byKey(const Key('addSetAdvancedTile')), findsOneWidget);
    });
  });
}
