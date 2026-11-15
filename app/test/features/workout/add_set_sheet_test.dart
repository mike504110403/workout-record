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
  bool compact = false,
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
                  compact: compact,
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
  group('長按連續加減', () {
    // 按下 → 400ms 起每 150ms 一次(含 400ms 那一刻),自按下起 1.5 秒後每 60ms。
    Future<TestGesture> hold(WidgetTester tester, String key) =>
        tester.startGesture(tester.getCenter(find.byKey(Key(key))));

    testWidgets('重量 +:按住 1 秒 → 400/550/700/850/1000ms 共 5 次;放開後不再變化', (tester) async {
      await _openSheet(tester);
      final g = await hold(tester, 'addSetWeightPlusButton');

      await tester.pump(const Duration(milliseconds: 399));
      expect(_text(tester, 'addSetWeightField'), '');
      await tester.pump(const Duration(milliseconds: 1)); // 400
      expect(_text(tester, 'addSetWeightField'), '2.5');
      await tester.pump(const Duration(milliseconds: 150)); // 550
      expect(_text(tester, 'addSetWeightField'), '5');
      await tester.pump(const Duration(milliseconds: 450)); // 1000
      expect(_text(tester, 'addSetWeightField'), '12.5');
      // 長按期間 Tooltip 浮層不出現(長按 400ms 先勝出,壓掉 tooltip 的 500ms)。
      expect(find.text('增加重量 (kg)'), findsNothing);

      await g.up();
      await tester.pump();
      expect(_text(tester, 'addSetWeightField'), '12.5'); // 放開不多加一次單點
      await tester.pump(const Duration(seconds: 2));
      expect(_text(tester, 'addSetWeightField'), '12.5');
    });

    testWidgets('按住超過 1.5 秒後加速到每 60ms', (tester) async {
      await _openSheet(tester);
      final g = await hold(tester, 'addSetWeightPlusButton');

      // 400 + 150k:400..1450 共 8 次,1600ms 是第 9 次(之後每 60ms)。
      await tester.pump(const Duration(milliseconds: 1500));
      expect(_text(tester, 'addSetWeightField'), '20'); // 8 次
      await tester.pump(const Duration(milliseconds: 100)); // 1600:第 9 次
      expect(_text(tester, 'addSetWeightField'), '22.5');
      await tester.pump(const Duration(milliseconds: 60)); // 1660
      expect(_text(tester, 'addSetWeightField'), '25');
      await tester.pump(const Duration(milliseconds: 120)); // 1720、1780
      expect(_text(tester, 'addSetWeightField'), '30');
      await g.up();
      await tester.pump();
    });

    testWidgets('重量 −:長按到 0 停在 0,不出現負數', (tester) async {
      await _openSheet(tester, initialWeight: 5, initialReps: 5);
      final g = await hold(tester, 'addSetWeightMinusButton');
      await tester.pump(const Duration(seconds: 2));
      expect(_text(tester, 'addSetWeightField'), '0');
      await g.up();
      await tester.pump();
      expect(_text(tester, 'addSetWeightField'), '0');
    });

    testWidgets('次數 +/−:同樣支援長按', (tester) async {
      await _openSheet(tester, initialWeight: 50, initialReps: 3);
      var g = await hold(tester, 'addSetRepsPlusButton');
      await tester.pump(const Duration(milliseconds: 700)); // 400/550/700
      await g.up();
      await tester.pump();
      expect(_text(tester, 'addSetRepsField'), '6');

      g = await hold(tester, 'addSetRepsMinusButton');
      await tester.pump(const Duration(seconds: 3));
      await g.up();
      await tester.pump();
      expect(_text(tester, 'addSetRepsField'), '0');
    });

    testWidgets('單點只步進一次:kg +2.5、lb +5;不到 400ms 放開不連發', (tester) async {
      await _openSheet(tester);
      await tester.tap(find.byKey(const Key('addSetWeightPlusButton')));
      await tester.pump(const Duration(seconds: 1));
      expect(_text(tester, 'addSetWeightField'), '2.5');
    });

    testWidgets('單點 lb 模式 +5', (tester) async {
      await _openSheet(tester, unit: WeightUnit.lb);
      await tester.tap(find.byKey(const Key('addSetWeightPlusButton')));
      await tester.pump(const Duration(seconds: 1));
      expect(_text(tester, 'addSetWeightField'), '5');
    });

    testWidgets('按住後拖出按鈕範圍:立即停止', (tester) async {
      await _openSheet(tester);
      final g = await hold(tester, 'addSetWeightPlusButton');
      await tester.pump(const Duration(milliseconds: 550));
      expect(_text(tester, 'addSetWeightField'), '5');
      await g.moveBy(const Offset(0, -300));
      await tester.pump(const Duration(seconds: 2));
      expect(_text(tester, 'addSetWeightField'), '5');
      await g.up();
      await tester.pump();
      expect(_text(tester, 'addSetWeightField'), '5');
    });

    testWidgets('長按中關閉視窗(dispose):不拋例外、無 pending timer', (tester) async {
      final h = await _openSheet(tester);
      final g = await hold(tester, 'addSetWeightPlusButton');
      await tester.pump(const Duration(milliseconds: 600));
      // 按住中從外部關閉 sheet。
      Navigator.of(tester.element(find.byKey(const Key('addSetWeightField'))), rootNavigator: true).pop();
      await tester.pumpAndSettle();
      expect(h().done, isTrue);
      expect(find.byKey(const Key('addSetWeightField')), findsNothing);
      await g.up();
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      // 測試結束時 framework 會檢查 pending timer(有殘留會報 A Timer is still pending)。
    });
  });

  group('重量快捷 +5/+10/+20', () {
    testWidgets('空欄 +10 → 10;62.5 +10 → 72.5;連點累加', (tester) async {
      await _openSheet(tester);
      await _tap(tester, 'addSetWeightQuick_10');
      expect(_text(tester, 'addSetWeightField'), '10');

      await tester.enterText(find.byKey(const Key('addSetWeightField')), '62.5');
      await _tap(tester, 'addSetWeightQuick_10');
      expect(_text(tester, 'addSetWeightField'), '72.5');
      await _tap(tester, 'addSetWeightQuick_5');
      await _tap(tester, 'addSetWeightQuick_20');
      expect(_text(tester, 'addSetWeightField'), '97.5');
    });

    testWidgets('快捷鈕點擊區 ≥48 高;次數沒有快捷鈕', (tester) async {
      await _openSheet(tester);
      for (final a in [5, 10, 20]) {
        expect(tester.getSize(find.byKey(Key('addSetWeightQuick_$a'))).height, greaterThanOrEqualTo(48));
      }
      expect(find.byKey(const Key('addSetRepsQuick_5')), findsNothing);
    });

    testWidgets('lb 模式:+10 是 10 lb,存檔回傳換算成 kg', (tester) async {
      final h = await _openSheet(tester, unit: WeightUnit.lb);
      await _tap(tester, 'addSetWeightQuick_10');
      expect(_text(tester, 'addSetWeightField'), '10');
      await tester.enterText(find.byKey(const Key('addSetRepsField')), '5');
      await tester.pump();
      await tester.tap(find.byKey(const Key('addSetSaveButton')));
      await tester.pumpAndSettle();
      expect(h().value!.weight, closeTo(10 / kLbPerKg, 1e-9));
    });

    testWidgets('kg 模式存檔回傳 +20 後的值', (tester) async {
      final h = await _openSheet(tester, initialWeight: 60, initialReps: 5);
      await _tap(tester, 'addSetWeightQuick_20');
      await tester.tap(find.byKey(const Key('addSetSaveButton')));
      await tester.pumpAndSettle();
      expect(h().value!.weight, 80);
    });
  });

  group('375x667 小螢幕不溢位', () {
    for (final compact in [true, false]) {
      testWidgets('compact=$compact 開視窗、展開進階選項無 overflow', (tester) async {
        tester.view.physicalSize = const Size(375, 667);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await _openSheet(tester, compact: compact, previousWeight: 60, previousReps: 8);
        expect(tester.takeException(), isNull);
        // 不捲動就點得到三顆快捷鈕(在視窗內且 hit-testable)。
        for (final a in [5, 10, 20]) {
          final f = find.byKey(Key('addSetWeightQuick_$a'));
          expect(f.hitTestable(), findsOneWidget);
          expect(const Rect.fromLTWH(0, 0, 375, 667).contains(tester.getRect(f).center), isTrue);
        }
        await tester.tap(find.byKey(const Key('addSetWeightQuick_20')));
        await tester.pump();
        expect(_text(tester, 'addSetWeightField'), '80');
        await tester.tap(find.text('進階選項'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
