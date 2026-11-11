// AboutPage widget seam:版本號顯示(package_info_plus 在測試環境用
// `PackageInfo.setMockInitialValues` mock,不打真的平台 channel)。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:workout_record/features/auth/session_controller.dart' show kAppleRevokeFailedMessage;
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
    // 舊的「裝置本機」宣稱不得殘留;App 無 analytics/crash SDK,不得宣稱收集。
    expect(find.textContaining('裝置本機'), findsNothing);
    expect(find.textContaining('使用數據'), findsNothing);
    expect(find.textContaining('錯誤報告'), findsNothing);
  });

  testWidgets('隱私內文涵蓋第三方、刪除帳號步驟、無追蹤廣告,且不殘留 Firebase/分析宣稱', (tester) async {
    // 拉高視窗,讓整頁都在畫面內(ListView 懶建置,避免後段內文沒 build)。
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 6000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: PrivacyPolicyPage()));
    await tester.pumpAndSettle();

    expect(find.textContaining('2026 年 11 月 12 日'), findsOneWidget);
    // 第三方:Supabase(含區域)與 Apple。
    expect(find.textContaining('Supabase'), findsWidgets);
    expect(find.textContaining('東京'), findsOneWidget);
    expect(find.textContaining('Sign in with Apple'), findsWidgets);
    // 刪除帳號具體步驟與撤銷 Apple 授權失敗的手動移除路徑。
    expect(find.textContaining('設定 > 刪除帳號'), findsWidgets);
    expect(find.textContaining('撤銷'), findsWidgets);
    expect(find.textContaining('iPhone 設定'), findsWidgets);
    // 只存本機的欄位要列全(含個人資料頁姓名),且說明可能含在使用者自己的裝置備份;
    // 引導頁的體重/目標體重/每週目標實際會上傳,要明說。
    expect(find.textContaining('身高、性別、年齡,以及個人資料頁的姓名'), findsOneWidget);
    expect(find.textContaining('不會上傳到我們的伺服器(可能包含在您自己的裝置備份中)'), findsOneWidget);
    expect(find.textContaining('體重、目標體重與每週目標會上傳'), findsOneWidget);
    // 登出不清全部本機資料:快取、草稿與舊版匯入資料保留到換帳號或刪帳號。
    expect(find.textContaining('訓練資料快取、進行中的草稿與舊版匯入資料會保留'), findsOneWidget);
    // 不承諾 App 內通知、不承諾處理時限。
    expect(find.textContaining('App 內通知'), findsNothing);
    // 追蹤與廣告:無。
    expect(find.textContaining('不含任何分析、廣告、追蹤'), findsOneWidget);
    // 舊版(Firebase/使用情況/診斷)宣稱不得殘留;沒有匯出功能就不宣稱。
    expect(find.textContaining('Firebase'), findsNothing);
    expect(find.textContaining('崩潰'), findsNothing);
    expect(find.textContaining('效能資料'), findsNothing);
    expect(find.textContaining('匯出'), findsNothing);
    expect(find.textContaining('加密'), findsNothing);
  });

  test('docs/privacy.html 與 App 內政策一致:無 Firebase/診斷段落,有 Supabase 與刪帳號步驟', () {
    final html = File('../docs/privacy.html').readAsStringSync();
    expect(html, contains('2026年11月12日'));
    expect(html, isNot(contains('Firebase')));
    expect(html, isNot(contains('使用情況資訊')));
    expect(html, isNot(contains('診斷資訊')));
    expect(html, isNot(contains('崩潰報告')));
    expect(html, contains('Supabase'));
    expect(html, contains('東京'));
    expect(html, contains('設定 > 刪除帳號'));
    expect(html, contains('Sign in with Apple'));
    // 手動移除路徑取自 App 實際顯示的常數,政策文字改動時兩邊不會悄悄分岔。
    final manualRemovePath =
        RegExp(r'可到 (.+?) 手動移除').firstMatch(kAppleRevokeFailedMessage)?.group(1);
    expect(manualRemovePath, isNotNull, reason: 'kAppleRevokeFailedMessage 句型變了,請同步此處擷取規則');
    expect(html, contains(manualRemovePath!));
    // 政策只寫 App 真有的機制、不承諾時限。
    expect(html, isNot(contains('在 App 內通知')));
    expect(html, isNot(contains('立即刪除')));
    expect(html, isNot(contains('盡快')));
    expect(html, contains('身高、性別、年齡，以及個人資料頁的姓名'));
    expect(html, contains('不會上傳到我們的伺服器（可能包含在您自己的裝置備份中）'));
    expect(html, contains('體重、目標體重與每週目標會上傳'));
    expect(html, contains('訓練資料快取、進行中的草稿與舊版匯入資料會保留'));
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
