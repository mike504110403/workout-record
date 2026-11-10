import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/core/theme/app_theme.dart';

void main() {
  group('AppSemanticColors', () {
    testWidgets('可從淺/深主題取得,且兩套顏色不同', (tester) async {
      AppSemanticColors? light;
      AppSemanticColors? dark;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              light = Theme.of(context).extension<AppSemanticColors>();
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) {
              dark = Theme.of(context).extension<AppSemanticColors>();
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle(); // AnimatedTheme 主題切換有 200ms 補間
      expect(light, isNotNull);
      expect(dark, isNotNull);
      expect(light!.pr, isNot(dark!.pr));
      expect(light!.success, isNot(dark!.success));
      expect(light!.muscleChest, isNot(dark!.muscleChest));
      expect(light!.muscleColors, hasLength(6));
      expect(dark!.muscleColors.toSet(), hasLength(6));
    });

    test('copyWith 只改指定欄位', () {
      const base = AppSemanticColors.light;
      final changed = base.copyWith(pr: Colors.black);
      expect(changed.pr, Colors.black);
      expect(changed.success, base.success);
      expect(changed.muscleCore, base.muscleCore);
    });

    test('lerp 端點與中點', () {
      const a = AppSemanticColors.light;
      const b = AppSemanticColors.dark;
      expect(a.lerp(b, 0).pr, a.pr);
      expect(a.lerp(b, 1).muscleArms, b.muscleArms);
      expect(a.lerp(b, 0.5).success, Color.lerp(a.success, b.success, 0.5));
      expect(a.lerp(null, 0.5), a);
    });

    testWidgets('context.semanticColors 在裸 ThemeData 下依亮度回退', (tester) async {
      late AppSemanticColors got;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Builder(
            builder: (context) {
              got = context.semanticColors;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(got, AppSemanticColors.dark);
    });
  });

  group('AppTheme 元件 theme', () {
    for (final entry in {
      'light': AppTheme.light,
      'dark': AppTheme.dark,
    }.entries) {
      test('${entry.key}: token 與元件設定套用正確', () {
        final t = entry.value;
        expect(t.useMaterial3, isTrue);
        expect(t.cardTheme.elevation, 0);
        expect(t.cardTheme.color, t.colorScheme.surfaceContainer);
        expect(
          (t.cardTheme.shape as RoundedRectangleBorder).borderRadius,
          AppRadius.cardRadius,
        );
        expect(t.inputDecorationTheme.filled, isTrue);
        expect(t.appBarTheme.centerTitle, isFalse);
        expect(t.appBarTheme.scrolledUnderElevation, 0);
        expect(t.bottomSheetTheme.showDragHandle, isTrue);
        expect(t.snackBarTheme.behavior, SnackBarBehavior.floating);
        final filled = t.filledButtonTheme.style!;
        expect(
          filled.minimumSize!.resolve({}),
          const Size(64, AppSizes.buttonHeight),
        );
        expect(t.extension<AppSemanticColors>(), isNotNull);
      });
    }

    test('token 值', () {
      expect(AppSpacing.xs, 4);
      expect(AppSpacing.sm, 8);
      expect(AppSpacing.md, 12);
      expect(AppSpacing.lg, 16);
      expect(AppSpacing.xl, 24);
      expect(AppSpacing.xxl, 32);
      expect(AppSpacing.pageHorizontal, 16);
      expect(AppRadius.card, 16);
      expect(AppRadius.control, 12);
      expect(AppRadius.chip, 8);
    });

    test('tabular helper 啟用 tabularFigures', () {
      final style = const TextStyle(fontSize: 12).tabular;
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
    });

    testWidgets('FilledButton 高度 48', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: FilledButton(onPressed: () {}, child: const Text('OK')),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(FilledButton)).height, 48);
    });
  });
}
