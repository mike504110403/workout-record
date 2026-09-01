// theme_preference.dart 的 provider seam 測試(波 6 B 工人真身)。
//
// 覆蓋範圍(逐項規則,不與其他三項偏好混測):
// - build():無任何值 → system;只有 legacy_theme → 預填生效;只有
//   legacy_is_dark_mode → 預填生效(theme 這項有兩個 legacy 來源,分開驗);
//   新 key 優先於兩個 legacy 來源;legacy_theme 值域畸形 → 落 system 不炸
//   (且刻意驗證此時「不」退回 legacy_is_dark_mode——見 theme_preference.dart
//   對這條判斷的說明)。
// - setThemeMode():寫入 SharedPreferences 並即時反映在 provider。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/settings/preferences/theme_preference.dart';

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
  group('themeModeProvider / ThemeModeController', () {
    test('無任何值(新 key 與兩個 legacy 都沒有)→ 預設 system', () async {
      final container = await _container();
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('只有 legacy_theme="dark" → legacy 預填生效', () async {
      final container = await _container(prefsValues: {kLegacyThemePrefsKey: 'dark'});
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('只有 legacy_is_dark_mode=true(沒有 legacy_theme)→ legacy 預填生效', () async {
      final container = await _container(prefsValues: {kLegacyIsDarkModePrefsKey: true});
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('只有 legacy_is_dark_mode=false(沒有 legacy_theme)→ 映射為淺色', () async {
      final container = await _container(prefsValues: {kLegacyIsDarkModePrefsKey: false});
      expect(container.read(themeModeProvider), ThemeMode.light);
    });

    test('新 key 與兩個 legacy 都種 → 新 key 優先', () async {
      final container = await _container(
        prefsValues: {
          kThemeModePrefsKey: 'light',
          kLegacyThemePrefsKey: 'dark',
          kLegacyIsDarkModePrefsKey: true,
        },
      );
      expect(container.read(themeModeProvider), ThemeMode.light);
    });

    test('legacy_theme 值域畸形(未知字串)→ 落安全預設 system,不炸', () async {
      final container = await _container(prefsValues: {kLegacyThemePrefsKey: 'sepia'});
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test(
        'legacy_theme 值域畸形時不退回 legacy_is_dark_mode——即使 is_dark_mode 也在,'
        '仍落 system(brief 判斷:新版本才有的欄位壞了不該用更舊訊號去猜)', () async {
      final container = await _container(
        prefsValues: {kLegacyThemePrefsKey: 'sepia', kLegacyIsDarkModePrefsKey: true},
      );
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('setThemeMode():寫入 SharedPreferences 並即時反映在 provider', () async {
      final container = await _container();
      expect(container.read(themeModeProvider), ThemeMode.system);

      await container.read(themeModeControllerProvider.notifier).setThemeMode(ThemeMode.dark);

      expect(container.read(themeModeProvider), ThemeMode.dark);
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString(kThemeModePrefsKey), 'dark');
    });
  });
}
