// ProfilePage widget seam:legacy 預填(既有值優先)、儲存寫入正確 key/型別、
// 失敗路徑不卡死不誤 pop。頁面一律被 push 進一個有底層路由的 Navigator
// (同 goal_settings_page_test.dart 慣例,`Navigator.pop()` 才有上一頁可
// 彈回去)。
//
// 變異清單:
//   - 拔預填 fallback(legacy_* 或 kUser*)必紅:「legacy 預填」「既有值優先
//     於 legacy」兩條分別守住。
//   - 拔儲存呼叫必紅:「儲存」直接查 prefs 三個 key 斷言型別與值。
//   - 拔 profile_filled_once 旗標(save 不設旗標,或 build 不看旗標)必紅:
//     「清空語義」三條——legacy/apple 建議不得在清空存檔後被填回;旗標隨
//     登出清除後新帳號重新預填。
//   - 儲存失敗仍解除 loading / 誤 pop 必紅:「儲存失敗」用 throwing writer,
//     斷言浮錯訊息、頁面沒被 pop、欄位與按鈕解除 disable。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/onboarding/onboarding_controller.dart'
    show kProfileFilledOnceKey, kUserGenderKey, kUserHeightKey, kUserNameKey;
import 'package:workout_record/features/settings/profile/profile_controller.dart';
import 'package:workout_record/features/settings/profile/profile_page.dart';

/// 失敗路徑用:寫入必拋錯(仿 dashboard_page_test.dart
/// `_ThrowingBodyWeightRepository` 慣例)。
class _ThrowingProfilePrefsWriter implements ProfilePrefsWriter {
  const _ThrowingProfilePrefsWriter();

  @override
  Future<void> write(
    SharedPreferences prefs, {
    required String name,
    required String gender,
    required double? heightCm,
  }) async {
    throw Exception('模擬個人資料存檔失敗(失敗路徑測試用)');
  }
}

Future<ProviderContainer> _buildContainer({
  Map<String, Object> prefsSeed = const {},
  ProfilePrefsWriter? writer,
}) async {
  SharedPreferences.setMockInitialValues(prefsSeed);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      if (writer != null) profilePrefsWriterProvider.overrideWithValue(writer),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// push 一個有底層路由的 Navigator,`ProfilePage` 被 push 上去——`_save()`
/// 內的 `Navigator.pop()` 才有上一頁可以彈回去。
Future<void> _pushProfilePage(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('openProfileButton'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ProfilePage()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('openProfileButton')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('legacy 預填:沒有既有 kUser* 值時,三欄帶入 legacy_user_* 的值', (tester) async {
    final container = await _buildContainer(
      prefsSeed: {
        kLegacyUserNameKey: 'Legacy Name',
        kLegacyUserGenderKey: '女性',
        kLegacyUserHeightKey: 165.5,
      },
    );
    await _pushProfilePage(tester, container);

    expect(find.text('Legacy Name'), findsOneWidget);
    expect(find.text('165.5'), findsOneWidget);
    final genderToggle = tester.widget<SegmentedButton<String>>(
      find.byKey(const Key('profileGenderToggle')),
    );
    expect(genderToggle.selected, {'女性'});
  });

  testWidgets('既有 kUser* 值優先於 legacy_*(兩組都種,顯示既有值)', (tester) async {
    final container = await _buildContainer(
      prefsSeed: {
        kUserNameKey: 'Existing Name',
        kLegacyUserNameKey: 'Legacy Name',
        kUserGenderKey: '男性',
        kLegacyUserGenderKey: '女性',
        kUserHeightKey: 180.0,
        kLegacyUserHeightKey: 165.5,
      },
    );
    await _pushProfilePage(tester, container);

    expect(find.text('Existing Name'), findsOneWidget);
    expect(find.text('Legacy Name'), findsNothing);
    expect(find.text('180.0'), findsOneWidget);
    expect(find.text('165.5'), findsNothing);
    final genderToggle = tester.widget<SegmentedButton<String>>(
      find.byKey(const Key('profileGenderToggle')),
    );
    expect(genderToggle.selected, {'男性'});
  });

  testWidgets('全空時,姓名欄用登入身分姓名(kAppleUserNameKey)當一次性預填建議,但不回寫 user_name', (tester) async {
    final container = await _buildContainer(
      prefsSeed: {
        kAppleUserIdKey: 'apple-user-1',
        kAppleUserNameKey: 'Apple Login Name',
      },
    );
    await _pushProfilePage(tester, container);

    expect(find.text('Apple Login Name'), findsOneWidget);

    // review 退回(存活變異):先前只斷言畫面顯示建議,沒有斷言「只預填不
    // 回寫」這半語義——光是看到建議、還沒按下儲存,`user_name` 必須仍是
    // null。直接查 prefs,不是只看畫面。
    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getString(kUserNameKey), isNull);

    // 沒按儲存就離開(pop)再重進:建議依然來自 apple 名,且 user_name 依然
    // 是 null——證明不是「第一次進頁的建議」湊巧沒被斷言到回寫,而是真的從未
    // 回寫過。比如未來若有人在 build() 裡加了「順手回寫」,會被這裡的第二次
    // 斷言逮到。
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('openProfileButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('openProfileButton')));
    await tester.pumpAndSettle();

    expect(find.text('Apple Login Name'), findsOneWidget);
    expect(prefs.getString(kUserNameKey), isNull);
  });

  testWidgets('儲存:prefs 三個 key 寫入正確型別與值', (tester) async {
    final container = await _buildContainer();
    await _pushProfilePage(tester, container);

    await tester.enterText(find.byKey(const Key('profileNameField')), 'Mike');
    await tester.tap(find.text('女性'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profileHeightField')), '178.5');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('saveProfileButton')));
    await tester.pumpAndSettle();

    // 存檔成功後頁面被 pop,回到開啟頁。
    expect(find.byKey(const Key('openProfileButton')), findsOneWidget);

    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getString(kUserNameKey), 'Mike');
    expect(prefs.getString(kUserGenderKey), '女性');
    expect(prefs.getDouble(kUserHeightKey), 178.5);
  });

  testWidgets('儲存失敗:顯示錯誤 SnackBar,頁面沒被 pop,欄位與按鈕解除 disable', (tester) async {
    final container = await _buildContainer(writer: const _ThrowingProfilePrefsWriter());
    await _pushProfilePage(tester, container);

    await tester.enterText(find.byKey(const Key('profileNameField')), 'Mike');
    await tester.tap(find.byKey(const Key('saveProfileButton')));
    await tester.pumpAndSettle();

    // 沒有被誤 pop:仍在個人資料頁,不是開啟頁。
    expect(find.byKey(const Key('openProfileButton')), findsNothing);
    expect(find.text('儲存失敗，請稍後再試'), findsOneWidget);

    final field = tester.widget<TextField>(find.byKey(const Key('profileNameField')));
    expect(field.enabled, isTrue);
    final button = tester.widget<FilledButton>(find.byKey(const Key('saveProfileButton')));
    expect(button.onPressed, isNotNull);
  });

  group('清空語義(預填一次性化,review MAJOR)', () {
    testWidgets('只有 legacy 值時,清空姓名與身高存檔 → 重進頁面兩欄為空,不被 legacy 回填', (tester) async {
      final container = await _buildContainer(
        prefsSeed: {
          kLegacyUserNameKey: 'Legacy Name',
          kLegacyUserHeightKey: 165.5,
        },
      );
      await _pushProfilePage(tester, container);
      expect(find.text('Legacy Name'), findsOneWidget);
      expect(find.text('165.5'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('profileNameField')), '');
      await tester.enterText(find.byKey(const Key('profileHeightField')), '');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveProfileButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('openProfileButton')), findsOneWidget);

      // prefs 層:空值誠實表現成「沒有 key」,旗標已設。
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.containsKey(kUserNameKey), isFalse);
      expect(prefs.containsKey(kUserHeightKey), isFalse);
      expect(prefs.getBool(kProfileFilledOnceKey), isTrue);

      // 畫面層:重進頁面,legacy 不得回填。
      await tester.tap(find.byKey(const Key('openProfileButton')));
      await tester.pumpAndSettle();
      expect(find.text('Legacy Name'), findsNothing);
      expect(find.text('165.5'), findsNothing);
      expect(tester.widget<TextField>(find.byKey(const Key('profileNameField'))).controller!.text, isEmpty);
      expect(tester.widget<TextField>(find.byKey(const Key('profileHeightField'))).controller!.text, isEmpty);
    });

    testWidgets('登入身分姓名(apple 建議)同理:清空姓名存檔後重進不被填回', (tester) async {
      final container = await _buildContainer(
        prefsSeed: {
          kAppleUserIdKey: 'apple-user-1',
          kAppleUserNameKey: 'Apple Login Name',
        },
      );
      await _pushProfilePage(tester, container);
      expect(find.text('Apple Login Name'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('profileNameField')), '');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveProfileButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('openProfileButton')));
      await tester.pumpAndSettle();
      expect(find.text('Apple Login Name'), findsNothing);
      expect(tester.widget<TextField>(find.byKey(const Key('profileNameField'))).controller!.text, isEmpty);
    });

    test('旗標屬個資清除清單:signOut 清掉旗標與姓名後,新帳號重新走 legacy 預填', () async {
      final container = await _buildContainer(
        prefsSeed: {
          kAppleUserIdKey: 'apple-user-1',
          kLegacyUserNameKey: 'Legacy Name',
          kUserNameKey: 'Saved Name',
          kProfileFilledOnceKey: true,
        },
      );
      // 存過檔 → 只看 stored 值。
      expect(container.read(profileControllerProvider).name, 'Saved Name');

      await container.read(sessionControllerProvider.notifier).signOut();

      // 清除後旗標與 user_name 都不在,provider 快取已跟著重算,回到 legacy 預填。
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.containsKey(kProfileFilledOnceKey), isFalse);
      expect(prefs.containsKey(kUserNameKey), isFalse);
      expect(container.read(profileControllerProvider).name, 'Legacy Name');
    });
  });
}
