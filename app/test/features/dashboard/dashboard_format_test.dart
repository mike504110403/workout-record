// dashboard_format 純函式測試。期望值一律寫死字面,不用正式換算函式現算。
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/features/dashboard/dashboard_format.dart';
import 'package:workout_record/features/settings/preferences/weight_unit.dart';

void main() {
  group('formatWeightChangeArrow', () {
    test('上升 ▲、下降 ▼,不帶單位', () {
      expect(formatWeightChangeArrow(1.2, WeightUnit.kg), '▲1.2');
      expect(formatWeightChangeArrow(-0.8, WeightUnit.kg), '▼0.8');
    });

    test('變化 0:只顯示 0.0,不帶箭頭', () {
      expect(formatWeightChangeArrow(0, WeightUnit.kg), '0.0');
      expect(formatWeightChangeArrow(0, WeightUnit.lb), '0.0');
    });

    test('四捨五入到 0.1 後為 0 也不帶箭頭(正負皆然)', () {
      expect(formatWeightChangeArrow(0.04, WeightUnit.kg), '0.0');
      expect(formatWeightChangeArrow(-0.04, WeightUnit.kg), '0.0');
    });

    test('lb 模式依單位換算(1.2 kg → 2.6 lb、-0.8 kg → 1.8 lb)', () {
      expect(formatWeightChangeArrow(1.2, WeightUnit.lb), '▲2.6');
      expect(formatWeightChangeArrow(-0.8, WeightUnit.lb), '▼1.8');
    });
  });
}
