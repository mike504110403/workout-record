import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/core/theme/app_theme.dart';
import 'package:workout_record/core/widgets/app_card.dart';
import 'package:workout_record/core/widgets/empty_state.dart';
import 'package:workout_record/core/widgets/metric_row.dart';
import 'package:workout_record/core/widgets/metric_tile.dart';
import 'package:workout_record/core/widgets/section_header.dart';

Future<void> _pump(WidgetTester tester, ThemeData theme, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  final themes = {'淺色': AppTheme.light, '深色': AppTheme.dark};

  for (final entry in themes.entries) {
    group('core widgets(${entry.key}主題)', () {
      final theme = entry.value;

      testWidgets('AppCard:顯示內容、預設 padding 16、無 onTap 無 InkWell', (
        tester,
      ) async {
        await _pump(tester, theme, const AppCard(child: Text('卡片內容')));
        expect(find.text('卡片內容'), findsOneWidget);
        final padding = tester.widget<Padding>(
          find.descendant(
            of: find.byType(AppCard),
            matching: find.byWidgetPredicate(
              (w) => w is Padding && w.child is Text,
            ),
          ),
        );
        expect(padding.padding, const EdgeInsets.all(16));
        expect(
          find.descendant(
            of: find.byType(AppCard),
            matching: find.byType(InkWell),
          ),
          findsNothing,
        );
      });

      testWidgets('AppCard:onTap 可點擊', (tester) async {
        var taps = 0;
        await _pump(
          tester,
          theme,
          AppCard(onTap: () => taps++, child: const Text('點我')),
        );
        await tester.tap(find.text('點我'));
        expect(taps, 1);
      });

      testWidgets('SectionHeader:標題與 trailing', (tester) async {
        var taps = 0;
        await _pump(
          tester,
          theme,
          SectionHeader(
            title: '本週',
            trailing: TextButton(
              onPressed: () => taps++,
              child: const Text('全部'),
            ),
          ),
        );
        expect(find.text('本週'), findsOneWidget);
        await tester.tap(find.text('全部'));
        expect(taps, 1);
      });

      testWidgets('SectionHeader:無 trailing 時只有標題', (tester) async {
        await _pump(tester, theme, const SectionHeader(title: '標題'));
        expect(find.text('標題'), findsOneWidget);
        expect(find.byType(TextButton), findsNothing);
      });

      testWidgets('MetricTile:數字、標籤、單位、趨勢,數字為 tabular', (tester) async {
        await _pump(
          tester,
          theme,
          const MetricTile(
            value: '12,500',
            label: '總量',
            unit: 'kg',
            trend: '+8%',
          ),
        );
        expect(find.text('總量'), findsOneWidget);
        expect(find.text('+8%'), findsOneWidget);
        expect(
          find.textContaining('12,500', findRichText: true),
          findsOneWidget,
        );
        expect(find.textContaining('kg', findRichText: true), findsOneWidget);
        final rich = tester.widget<RichText>(
          find.descendant(
            of: find.byType(MetricTile),
            matching: find.byWidgetPredicate(
              (w) => w is RichText && w.text.toPlainText().contains('12,500'),
            ),
          ),
        );
        TextSpan? valueSpan;
        rich.text.visitChildren((span) {
          if (span is TextSpan && span.text == '12,500') valueSpan = span;
          return true;
        });
        expect(
          valueSpan!.style!.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
      });

      testWidgets('MetricTile:只有必填欄位時不顯示單位與趨勢', (tester) async {
        await _pump(tester, theme, const MetricTile(value: '3', label: '次數'));
        expect(find.text('3'), findsOneWidget);
        expect(find.text('次數'), findsOneWidget);
      });

      testWidgets('MetricRow:多個 tile 等分寬度', (tester) async {
        await _pump(
          tester,
          theme,
          const MetricRow(
            tiles: [
              MetricTile(value: '1', label: 'A'),
              MetricTile(value: '2', label: 'B'),
              MetricTile(value: '3', label: 'C'),
            ],
          ),
        );
        expect(find.byType(MetricTile), findsNWidgets(3));
        final w = [
          for (final e in find.byType(Expanded).evaluate())
            tester.getSize(find.byWidget(e.widget)).width,
        ];
        expect(w, hasLength(3));
        expect(w[0], closeTo(w[1], 0.01));
        expect(w[1], closeTo(w[2], 0.01));
      });

      testWidgets('EmptyState:完整內容與按鈕回呼', (tester) async {
        var taps = 0;
        await _pump(
          tester,
          theme,
          SizedBox(
            height: 500,
            child: EmptyState(
              icon: Icons.fitness_center,
              title: '還沒有紀錄',
              message: '開始第一次訓練吧',
              actionLabel: '開始訓練',
              onAction: () => taps++,
            ),
          ),
        );
        expect(find.byIcon(Icons.fitness_center), findsOneWidget);
        expect(find.text('還沒有紀錄'), findsOneWidget);
        expect(find.text('開始第一次訓練吧'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, '開始訓練'));
        expect(taps, 1);
      });

      testWidgets('EmptyState:未提供 action 時不顯示按鈕', (tester) async {
        await _pump(
          tester,
          theme,
          const SizedBox(
            height: 500,
            child: EmptyState(icon: Icons.inbox, title: '空'),
          ),
        );
        expect(find.text('空'), findsOneWidget);
        expect(find.byType(FilledButton), findsNothing);
      });
    });
  }
}
