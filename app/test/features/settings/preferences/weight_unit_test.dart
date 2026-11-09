// weight_unit.dart 的 provider seam 測試(波 6 B 工人真身)。
//
// 覆蓋範圍(逐項規則,不與其他三項偏好混測——見 brief「一個 fixture 混測
// 四項」的禁令):
// - build():無任何值 → kg;只有 legacy_weight_unit → 預填生效;新 key 優先
//   於 legacy;legacy 畸形值 → 落 kg 不炸。
// - setUnit():寫入 SharedPreferences 並即時反映在 provider(state)。
// - 契約回歸:C 工人 22 個檔案消費 weightUnitProvider,無任何 prefs 值時必須
//   回 kg——這條刻意獨立成一個測試案例,標題直接點名「契約回歸」方便將來
//   誰改壞了一眼看到。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/settings/preferences/weight_unit.dart';

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
  group('weightUnitProvider / WeightUnitController', () {
    test('無任何值(新 key 與 legacy 都沒有)→ 預設 kg', () async {
      final container = await _container();
      expect(container.read(weightUnitProvider), WeightUnit.kg);
    });

    test('契約回歸:C 工人消費基準——weightUnitProvider 無任何 prefs 值時回 kg', () async {
      final container = await _container();
      expect(container.read(weightUnitProvider), WeightUnit.kg);
    });

    test('只有 legacy_weight_unit="lb" → legacy 預填生效', () async {
      final container = await _container(prefsValues: {kLegacyWeightUnitPrefsKey: 'lb'});
      expect(container.read(weightUnitProvider), WeightUnit.lb);
    });

    test('新 key 與 legacy 都種(kg 與 lb 不同值)→ 新 key 優先', () async {
      final container = await _container(
        prefsValues: {kWeightUnitPrefsKey: 'lb', kLegacyWeightUnitPrefsKey: 'kg'},
      );
      expect(container.read(weightUnitProvider), WeightUnit.lb);
    });

    test('legacy_weight_unit 值域畸形(未知字串)→ 落安全預設 kg,不炸', () async {
      final container = await _container(
        prefsValues: {kLegacyWeightUnitPrefsKey: 'stone'},
      );
      expect(container.read(weightUnitProvider), WeightUnit.kg);
    });

    test('setUnit():寫入 SharedPreferences 並即時反映在 provider', () async {
      final container = await _container();
      expect(container.read(weightUnitProvider), WeightUnit.kg);

      await container.read(weightUnitControllerProvider.notifier).setUnit(WeightUnit.lb);

      expect(container.read(weightUnitProvider), WeightUnit.lb);
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString(kWeightUnitPrefsKey), 'lb');
    });
  });
}
