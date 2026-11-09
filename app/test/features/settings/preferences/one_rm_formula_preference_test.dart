// one_rm_formula_preference.dart 的 provider seam 測試(波 6 B 工人真身)。
//
// 覆蓋範圍(逐項規則,不與其他三項偏好混測):
// - build():無任何值 → epley;只有 legacy_one_rm_formula → 預填生效;新 key
//   優先於 legacy;legacy_one_rm_formula 值域畸形 → 落安全預設 epley 不炸。
// - setFormula():寫入 SharedPreferences 並即時反映在 provider。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/settings/preferences/one_rm_formula_preference.dart';

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
  group('oneRmFormulaProvider / OneRmFormulaController', () {
    test('無任何值(新 key 與 legacy 都沒有)→ 預設 epley', () async {
      final container = await _container();
      expect(container.read(oneRmFormulaProvider), OneRmFormula.epley);
    });

    test('只有 legacy_one_rm_formula="brzycki" → legacy 預填生效', () async {
      final container = await _container(
        prefsValues: {kLegacyOneRmFormulaPrefsKey: 'brzycki'},
      );
      expect(container.read(oneRmFormulaProvider), OneRmFormula.brzycki);
    });

    test('新 key 與 legacy 都種(不同值)→ 新 key 優先', () async {
      final container = await _container(
        prefsValues: {
          kOneRmFormulaPrefsKey: 'lander',
          kLegacyOneRmFormulaPrefsKey: 'brzycki',
        },
      );
      expect(container.read(oneRmFormulaProvider), OneRmFormula.lander);
    });

    test('legacy_one_rm_formula 值域畸形(未知字串)→ 落安全預設 epley,不炸', () async {
      final container = await _container(
        prefsValues: {kLegacyOneRmFormulaPrefsKey: 'oconner'},
      );
      expect(container.read(oneRmFormulaProvider), OneRmFormula.epley);
    });

    test('setFormula():寫入 SharedPreferences 並即時反映在 provider', () async {
      final container = await _container();
      expect(container.read(oneRmFormulaProvider), OneRmFormula.epley);

      await container
          .read(oneRmFormulaControllerProvider.notifier)
          .setFormula(OneRmFormula.lander);

      expect(container.read(oneRmFormulaProvider), OneRmFormula.lander);
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString(kOneRmFormulaPrefsKey), 'lander');
    });
  });
}
