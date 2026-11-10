// Y 軸刻度格式化純函式 + 標籤 widget 的單元測試。參照值全部手算。
// 回歸背景:體重圖左軸 reservedSize 40 又沒自訂格式,"72.4" 這類標籤被擠成兩行
// 疊字("72.4/0")。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/features/stats/chart_axis_format.dart';

void main() {
  group('formatYAxisLabel', () {
    test('整數間隔 → 整數(去掉浮點雜訊)', () {
      expect(formatYAxisLabel(72, interval: 2), '72');
      expect(formatYAxisLabel(72.00000000001, interval: 5), '72');
      expect(formatYAxisLabel(100, interval: 10), '100');
    });

    test('小數或 <1 的間隔 → 1 位小數,同軸標籤小數位一致', () {
      expect(formatYAxisLabel(72.5, interval: 0.5), '72.5');
      expect(formatYAxisLabel(73, interval: 0.5), '73.0');
      expect(formatYAxisLabel(72.4, interval: 2.5), '72.4');
      expect(formatYAxisLabel(72.39999999, interval: 0.2), '72.4');
    });

    test('-0 不顯示負號', () {
      expect(formatYAxisLabel(-0.04, interval: 1), '0');
      expect(formatYAxisLabel(-0.04, interval: 0.5), '0.0');
      expect(formatYAxisLabel(-5, interval: 5), '-5');
    });

    test('compactThousands:>=1000 輸出 k,其餘照整數規則', () {
      expect(formatYAxisLabel(1500, interval: 500, compactThousands: true), '1.5k');
      expect(formatYAxisLabel(12000, interval: 2000, compactThousands: true), '12.0k');
      expect(formatYAxisLabel(800, interval: 200, compactThousands: true), '800');
      // 未開啟時 1500 保持完整數字。
      expect(formatYAxisLabel(1500, interval: 500), '1500');
    });
  });

  testWidgets('yAxisTitle 渲染單行(maxLines 1、不換行),字串走 formatYAxisLabel', (tester) async {
    late Widget title;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: kYAxisReservedSize,
            child: Builder(
              builder: (context) {
                title = yAxisTitle(
                  72.4,
                  TitleMeta(
                    min: 70,
                    max: 80,
                    parentAxisSize: 200,
                    axisPosition: 0,
                    appliedInterval: 0.5,
                    sideTitles: const SideTitles(),
                    formattedValue: '72.4',
                    axisSide: AxisSide.left,
                    rotationQuarterTurns: 0,
                  ),
                );
                return title;
              },
            ),
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('72.4'));
    expect(text.maxLines, 1);
    expect(text.softWrap, isFalse);
    // 單行高度:不會因為寬度不足換成兩行。
    expect(tester.getSize(find.text('72.4')).height, lessThan(24));
  });
}
