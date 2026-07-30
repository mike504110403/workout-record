// ImportRetryTile 的 widget test(spec 4.6 節「手動重試」UI)。
//
// 只驗證 widget 本身的顯示/互動邏輯:是否可以透過建構子注入的
// checkPermanentlyFailed / importAction 覆寫真正的 SharedPreferences /
// CoreDataImporter,不需要搭一整棵 provider tree 或 mock platform channel
// (ImportRetryTile 本身的預設路徑——真正讀 SharedPreferences、真正呼叫
// CoreDataImporter——已經被 coredata_importer_test.dart 間接覆蓋)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/data/migration/coredata_importer.dart';
import 'package:workout_record/features/settings/widgets/import_retry_tile.dart';

void main() {
  setUp(() {
    // _retry() 內部仍會呼叫 SharedPreferences.getInstance() 清旗標/計數
    // (即使匯入動作本身由 importAction 注入的假函式接管),這裡先給一份
    // mock 初始值,避免走到真正的 platform channel。
    SharedPreferences.setMockInitialValues({});
  });

  Widget wrap(Widget child) {
    return ProviderScope(
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  /// 點擊重試按鈕後,_retry() 會先 setState 顯示轉圈(不確定進度的
  /// CircularProgressIndicator,動畫永不停止),`pumpAndSettle` 因此永遠
  /// 等不到「沒有排程中的畫面更新」而逾時——改用固定次數的 `pump` 手動推進
  /// 到 async 呼叫鏈跑完(importAction 本身不帶真正的延遲,幾個 microtask
  /// 就能跑完)。
  Future<void> tapRetryAndDrain(WidgetTester tester) async {
    await tester.tap(find.text('重新匯入舊資料'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('旗標為 false 時不渲染任何東西', (tester) async {
    await tester.pumpWidget(
      wrap(
        ImportRetryTile(
          checkPermanentlyFailed: () async => false,
          importAction: () async => const ImportResult.skippedNoOldDb(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('舊資料匯入失敗'), findsNothing);
    expect(find.text('重新匯入舊資料'), findsNothing);
  });

  testWidgets('旗標為 true 時渲染重試按鈕', (tester) async {
    await tester.pumpWidget(
      wrap(
        ImportRetryTile(
          checkPermanentlyFailed: () async => true,
          importAction: () async => const ImportResult.skippedNoOldDb(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('舊資料匯入失敗'), findsOneWidget);
    expect(find.text('重新匯入舊資料'), findsOneWidget);
  });

  testWidgets('點擊重試按鈕觸發 importAction 回呼,成功後顯示成功 SnackBar', (tester) async {
    var callCount = 0;

    await tester.pumpWidget(
      wrap(
        ImportRetryTile(
          checkPermanentlyFailed: () async => true,
          importAction: () async {
            callCount++;
            return const ImportResult(
              success: true,
              skipped: false,
              tableCounts: {'workouts': 3},
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tapRetryAndDrain(tester);

    expect(callCount, 1);
    expect(find.text('舊資料重新匯入成功'), findsOneWidget);
  });

  testWidgets('點擊重試按鈕,失敗時顯示失敗 SnackBar 並保留錯誤訊息', (tester) async {
    await tester.pumpWidget(
      wrap(
        ImportRetryTile(
          checkPermanentlyFailed: () async => true,
          importAction: () async => const ImportResult(
            success: false,
            skipped: false,
            errorMessage: 'boom',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tapRetryAndDrain(tester);

    expect(find.text('重新匯入仍失敗:boom'), findsOneWidget);
  });
}
