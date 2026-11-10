// RestTimerBar:自然倒數結束跳「休息時間結束」提示(對照 iOS WorkoutView 的
// alert);跳過與手動調到 0 不跳。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_record/features/workout/rest_timer_bar.dart';
import 'package:workout_record/features/workout/rest_timer_controller.dart';

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [restTimerFinishedFeedbackProvider.overrideWithValue(() {})],
  );
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
  testWidgets('自然倒數結束 → 跳提示含動作名稱,按「知道了」關閉', (tester) async {
    final container = await _pump(tester);
    container.read(restTimerControllerProvider.notifier).start(seconds: 2, exerciseName: '深蹲');
    await tester.pump();
    expect(find.byKey(const Key('restTimerBar')), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('restFinishedDialog')), findsOneWidget);
    expect(find.text('休息時間結束'), findsOneWidget);
    expect(find.text('準備好進行下一組 深蹲 了嗎?'), findsOneWidget);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('restFinishedDialog')), findsNothing);
  });

  testWidgets('跳過或手動調到 0 不跳提示', (tester) async {
    final container = await _pump(tester);
    final notifier = container.read(restTimerControllerProvider.notifier);

    notifier.start(seconds: 30);
    await tester.pump();
    notifier.skip();
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('restFinishedDialog')), findsNothing);

    notifier.start(seconds: 15);
    await tester.pump();
    notifier.adjust(-15);
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('restFinishedDialog')), findsNothing);
  });
}
