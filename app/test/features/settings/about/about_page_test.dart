// AboutPage widget seam:版本號顯示(package_info_plus 在測試環境用
// `PackageInfo.setMockInitialValues` mock,不打真的平台 channel)。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:workout_record/features/settings/about/about_page.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'WorkItOut',
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

  testWidgets('隱私內文不宣稱匯出/刪除帳號功能(與現況不符,brief 明定要刪掉)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pumpAndSettle();

    expect(find.textContaining('匯出'), findsNothing);
    expect(find.textContaining('刪除帳'), findsNothing);
    // 現況陳述必須在:資料存裝置本機、不上傳雲端(隱私文案紀律)。
    expect(find.textContaining('裝置本機'), findsOneWidget);
  });
}
