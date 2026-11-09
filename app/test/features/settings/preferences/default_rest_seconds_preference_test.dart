// default_rest_seconds_preference.dart 的 provider seam 測試(波 6 B 工人
// 真身)。
//
// 覆蓋範圍(逐項規則,不與其他三項偏好混測):
// - build():無任何值 → 現行常數 kDefaultRestSeconds(90);只有
//   legacy_default_rest_time → 預填生效;新 key 優先於 legacy;
//   legacy_default_rest_time 為 0 或負數(畸形值,brief 明定案例)→ 落安全
//   預設不炸。
// - setSeconds():寫入 SharedPreferences 並即時反映在 provider。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/settings/preferences/default_rest_seconds_preference.dart';
import 'package:workout_record/features/workout/workout_ui_shared.dart' show kDefaultRestSeconds;

Future<ProviderContainer> _container({Map<String, Object> prefsValues = const {}}) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('defaultRestSecondsProvider / DefaultRestSecondsController', () {
    test('無任何值(新 key 與 legacy 都沒有)→ 沿用現行常數 kDefaultRestSeconds(90)', () async {
      final container = await _container();
      expect(container.read(defaultRestSecondsProvider), kDefaultRestSeconds);
      expect(container.read(defaultRestSecondsProvider), 90);
    });

    test('只有 legacy_default_rest_time=120 → legacy 預填生效', () async {
      final container = await _container(
        prefsValues: {kLegacyDefaultRestTimePrefsKey: 120},
      );
      expect(container.read(defaultRestSecondsProvider), 120);
    });

    test('新 key 與 legacy 都種(不同值)→ 新 key 優先', () async {
      final container = await _container(
        prefsValues: {kDefaultRestSecondsPrefsKey: 60, kLegacyDefaultRestTimePrefsKey: 180},
      );
      expect(container.read(defaultRestSecondsProvider), 60);
    });

    test('legacy_default_rest_time=0(畸形值,brief 明定案例)→ 落安全預設 90,不炸', () async {
      final container = await _container(
        prefsValues: {kLegacyDefaultRestTimePrefsKey: 0},
      );
      expect(container.read(defaultRestSecondsProvider), kDefaultRestSeconds);
    });

    test('legacy_default_rest_time=-30(負數,畸形值)→ 落安全預設 90,不炸', () async {
      final container = await _container(
        prefsValues: {kLegacyDefaultRestTimePrefsKey: -30},
      );
      expect(container.read(defaultRestSecondsProvider), kDefaultRestSeconds);
    });

    test('setSeconds():寫入 SharedPreferences 並即時反映在 provider', () async {
      final container = await _container();
      expect(container.read(defaultRestSecondsProvider), kDefaultRestSeconds);

      await container.read(defaultRestSecondsControllerProvider.notifier).setSeconds(150);

      expect(container.read(defaultRestSecondsProvider), 150);
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getInt(kDefaultRestSecondsPrefsKey), 150);
    });
  });
}
