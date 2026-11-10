// AboutPage widget seam:版本號顯示(package_info_plus 在測試環境用
// `PackageInfo.setMockInitialValues` mock,不打真的平台 channel)。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:workout_record/features/settings/about/about_page.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Work It Out',
      packageName: 'com.mikelin.workitout',
      version: '2.0.0',
      buildNumber: '6',
      buildSignature: '',
    );
  });

  testWidgets('顯示 PackageInfo 的 version + buildNumber', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('aboutVersionText')), findsOneWidget);
    expect(find.text('版本 2.0.0 (6)'), findsOneWidget);
  });

  testWidgets('隱私內文不宣稱匯出;刪除帳號指向設定頁', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pumpAndSettle();

    expect(find.textContaining('匯出'), findsNothing);
    expect(find.textContaining('設定 > 刪除帳號'), findsOneWidget);
    // 現況陳述必須在:登入後資料存雲端(Supabase)、僅本人可存取(隱私文案紀律)。
    expect(find.textContaining('雲端伺服器(Supabase)'), findsOneWidget);
    expect(find.textContaining('只有您本人'), findsOneWidget);
    // 舊的本機/不上傳宣稱不得殘留;App 無 analytics/crash SDK,不得宣稱收集。
    expect(find.textContaining('不會上傳'), findsNothing);
    expect(find.textContaining('裝置本機'), findsNothing);
    expect(find.textContaining('使用數據'), findsNothing);
    expect(find.textContaining('錯誤報告'), findsNothing);
  });

  testWidgets('功能特色區:只列 Flutter 真有的功能,不含成就', (tester) async {
    // 拉高視窗,讓整頁(含長頁尾段的功能特色區)都在畫面內。
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 3000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pumpAndSettle();

    expect(find.text('功能特色'), findsOneWidget);
    for (final title in ['數據分析', 'PR 追蹤', '目標追蹤', '三項力量']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('詳細的訓練數據分析與趨勢圖表'), findsOneWidget);
    expect(find.text('設定並追蹤您的健身目標'), findsOneWidget);
    expect(find.text('專業的深蹲、臥推、硬舉記錄'), findsOneWidget);
    expect(find.textContaining('成就'), findsNothing);
  });

  testWidgets('開發者列顯示 Mike Lin', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('aboutDeveloperTile')),
      200,
    );
    await tester.pumpAndSettle();

    expect(find.text('開發者'), findsOneWidget);
    expect(find.text('Mike Lin'), findsOneWidget);
  });

  testWidgets('父層 rebuild(新的 AboutPage 實例)不重新查詢版本——不閃回轉圈圈(review minor)', (tester) async {
    final tick = ValueNotifier<int>(0);
    addTearDown(tick.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<int>(
          valueListenable: tick,
          // 刻意不加 const:每次 builder 重跑都產生新的 AboutPage 實例,State
          // 沿用但 build() 會重跑——future 若在 build() 內建立就會被換新。
          // ignore: prefer_const_constructors
          builder: (_, _, _) => AboutPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('版本 2.0.0 (6)'), findsOneWidget);

    tick.value++;
    // 只 pump 一幀(不 settle):future 若在 build 內重建,這一幀會是轉圈圈。
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('版本 2.0.0 (6)'), findsOneWidget);
  });

  testWidgets('點聯絡我們 → 複製信箱並提示', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('aboutContactTile')), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('aboutContactTile')));
    await tester.pumpAndSettle();

    expect(copied, kContactEmail);
    expect(find.text('已複製聯絡信箱'), findsOneWidget);
  });

  testWidgets('點服務條款 → 進入條款頁', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('aboutTermsTile')), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('aboutTermsTile')));
    await tester.pumpAndSettle();

    expect(find.byType(TermsOfServicePage), findsOneWidget);
    expect(find.text('免責聲明'), findsOneWidget);
  });
}
