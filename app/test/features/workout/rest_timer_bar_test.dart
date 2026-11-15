// RestTimerBar:自然倒數結束在原計時列位置顯示列內提示(取代 AlertDialog,
// 約 4 秒自動消失、點一下可關閉);跳過與手動調到 0 不顯示。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_record/features/workout/rest_timer_bar.dart';
import 'package:workout_record/features/workout/rest_timer_controller.dart';

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final container = ProviderContainer(overrides: [restTimerFinishedFeedbackProvider.overrideWithValue(() {})]);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: RestTimerBar())),
    ),
  );
  return container;
}

void main() {
  testWidgets('自然倒數結束 → 原位置顯示列內提示含動作名稱,4 秒後自動消失,不出現對話框', (tester) async {
    final container = await _pump(tester);
    container.read(restTimerControllerProvider.notifier).start(seconds: 2, exerciseName: '深蹲');
    await tester.pump();
    expect(find.byKey(const Key('restTimerBar')), findsOneWidget);
    expect(find.byKey(const Key('restFinishedBanner')), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('restTimerBar')), findsNothing);
    expect(find.byKey(const Key('restFinishedBanner')), findsOneWidget);
    expect(find.text('休息結束・準備下一組 深蹲'), findsOneWidget);
    expect(find.byKey(const Key('restFinishedDialog')), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(const Duration(milliseconds: 3900));
    expect(find.byKey(const Key('restFinishedBanner')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('restFinishedBanner')), findsNothing);
  });

  testWidgets('提示:無動作名稱時文字不帶動作;點一下可關閉', (tester) async {
    final container = await _pump(tester);
    container.read(restTimerControllerProvider.notifier).start(seconds: 1);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('休息結束・準備下一組'), findsOneWidget);

    await tester.tap(find.byKey(const Key('restFinishedBanner')));
    await tester.pump();
    expect(find.byKey(const Key('restFinishedBanner')), findsNothing);
    // 手動關閉後 4 秒計時不得殘留(flutter_test 會斷言沒有 pending timer)。
  });

  testWidgets('提示顯示中又 start:提示立即消失、換回倒數列', (tester) async {
    final container = await _pump(tester);
    final notifier = container.read(restTimerControllerProvider.notifier);
    notifier.start(seconds: 1, exerciseName: '深蹲');
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('restFinishedBanner')), findsOneWidget);

    notifier.start(seconds: 30, exerciseName: '深蹲');
    await tester.pump();
    expect(find.byKey(const Key('restFinishedBanner')), findsNothing);
    expect(find.byKey(const Key('restTimerBar')), findsOneWidget);

    // 舊的 4 秒消失計時不得讓新的倒數列出狀況。
    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const Key('restTimerBar')), findsOneWidget);

    // 提示不得只是被倒數列蓋住:新倒數被跳過後,舊提示不能再冒出來。
    notifier.start(seconds: 1, exerciseName: '深蹲');
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('restFinishedBanner')), findsOneWidget);
    notifier.start(seconds: 30, exerciseName: '深蹲');
    await tester.pump();
    notifier.skip();
    await tester.pump();
    expect(find.byKey(const Key('restFinishedBanner')), findsNothing);
  });

  testWidgets('跳過或手動調到 0 不顯示提示', (tester) async {
    final container = await _pump(tester);
    final notifier = container.read(restTimerControllerProvider.notifier);

    notifier.start(seconds: 30);
    await tester.pump();
    notifier.skip();
    await tester.pump(const Duration(seconds: 31));
    expect(find.byKey(const Key('restFinishedBanner')), findsNothing);
    expect(find.byKey(const Key('restFinishedDialog')), findsNothing);

    notifier.start(seconds: 15);
    await tester.pump();
    notifier.adjust(-15);
    await tester.pump(const Duration(seconds: 16));
    expect(find.byKey(const Key('restFinishedBanner')), findsNothing);
    expect(find.byKey(const Key('restFinishedDialog')), findsNothing);
  });

  testWidgets('−15 / +15 / 跳過 的點擊區至少 48x48', (tester) async {
    final container = await _pump(tester);
    container.read(restTimerControllerProvider.notifier).start(seconds: 60, exerciseName: '深蹲');
    await tester.pump();

    for (final key in ['restTimerMinus15Button', 'restTimerPlus15Button', 'restTimerSkipButton']) {
      final size = tester.getSize(find.byKey(Key(key)));
      expect(size.width, greaterThanOrEqualTo(48), reason: '$key 寬');
      expect(size.height, greaterThanOrEqualTo(48), reason: '$key 高');
    }

    // 收掉 Timer.periodic,避免測試結束時 pending timer 斷言。
    container.read(restTimerControllerProvider.notifier).skip();
    await tester.pump();
  });
}
