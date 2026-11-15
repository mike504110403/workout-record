// RestTimerController 計時器測試:用 `tester.pump(Duration)` 控制虛擬時間
// (flutter_test 的 AutomatedTestWidgetsFlutterBinding 在 FakeAsync zone 內跑
// 測試本體,`Timer.periodic` 天生能被 pump 推進,不需要真的等待)。
import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_record/features/workout/rest_notification_scheduler.dart';
import 'package:workout_record/features/workout/rest_timer_controller.dart';

import 'fake_rest_notification_scheduler.dart';

ProviderContainer _containerWith(
  FakeRestNotificationScheduler scheduler, {
  void Function()? feedback,
  bool Function()? inForeground,
}) {
  final container = ProviderContainer(
    overrides: [
      restNotificationSchedulerProvider.overrideWithValue(scheduler),
      restTimerFinishedFeedbackProvider.overrideWithValue(feedback ?? () {}),
      if (inForeground != null) restTimerAppInForegroundProvider.overrideWithValue(inForeground),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

final _t0 = DateTime.utc(2026, 1, 1, 12);
String _sched(DateTime at, [String? name]) => 'schedule(${at.toIso8601String()},$name)';

void main() {
  testWidgets('start:啟動倒數,每秒遞減,歸零後自動停止', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(restTimerControllerProvider.notifier);

    notifier.start(seconds: 5, exerciseName: '槓鈴臥推');
    expect(container.read(restTimerControllerProvider).remainingSeconds, 5);
    expect(container.read(restTimerControllerProvider).isRunning, isTrue);
    expect(container.read(restTimerControllerProvider).exerciseName, '槓鈴臥推');

    await tester.pump(const Duration(seconds: 1));
    expect(container.read(restTimerControllerProvider).remainingSeconds, 4);

    await tester.pump(const Duration(seconds: 4));
    expect(container.read(restTimerControllerProvider).remainingSeconds, 0);
    expect(container.read(restTimerControllerProvider).isRunning, isFalse);

    // 歸零後不再繼續遞減(不會變負數)。
    await tester.pump(const Duration(seconds: 2));
    expect(container.read(restTimerControllerProvider).remainingSeconds, 0);
  });

  // 矩陣:「休息計時中儲存下一組 → 重啟計時器」的底層防護——[start] 一律先
  // 取消既有 Timer 再重新起算,不論目前是否正在跑。雙向變異:把
  // rest_timer_controller.dart `start()` 開頭的 `_timer?.cancel(); _timer =
  // null;` 拿掉,這則測試會紅(舊的 timer 繼續跑,新舊兩個 timer 交錯遞減,
  // pump(10s) 後 remainingSeconds 不會剛好是 10)。
  testWidgets('start 重啟:倒數中再次呼叫 start,取消舊計時器、重新起算', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(restTimerControllerProvider.notifier);

    notifier.start(seconds: 10, exerciseName: '深蹲');
    await tester.pump(const Duration(seconds: 3));
    expect(container.read(restTimerControllerProvider).remainingSeconds, 7);

    // 中途存了下一組,重啟成新的 20 秒倒數(對照「上一組」休息還沒結束
    // 就記錄下一組的情境)。
    notifier.start(seconds: 20, exerciseName: '深蹲');
    expect(container.read(restTimerControllerProvider).remainingSeconds, 20);

    await tester.pump(const Duration(seconds: 10));
    // 若舊的 7 秒倒數沒被取消,它會在重啟後 7 秒(也就是這次 pump 的時間點
    // 附近)額外觸發一次遞減或 stop,讓這裡的數字對不上。剛好等於
    // 20 - 10 = 10 才代表只有「新」計時器在跑。
    expect(container.read(restTimerControllerProvider).remainingSeconds, 10);
    expect(container.read(restTimerControllerProvider).isRunning, isTrue);

    // 收尾清掉還在跑的 periodic Timer——flutter_test 在測試結束時會斷言
    // 沒有殘留的 pending timer,`container.dispose()` 雖然會經
    // `ref.onDispose` 取消,但那發生在 addTearDown 階段,保險起見這裡先
    // 主動停止,不依賴 teardown 的時序。
    notifier.skip();
  });

  testWidgets('adjust:±15 秒,超過原總秒數時 totalSeconds 跟著拉高', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(restTimerControllerProvider.notifier);

    notifier.start(seconds: 30);
    notifier.adjust(-15);
    expect(container.read(restTimerControllerProvider).remainingSeconds, 15);

    notifier.adjust(15);
    expect(container.read(restTimerControllerProvider).remainingSeconds, 30);

    notifier.adjust(15);
    expect(container.read(restTimerControllerProvider).remainingSeconds, 45);
    expect(container.read(restTimerControllerProvider).totalSeconds, 45);

    notifier.skip(); // 收尾清掉還在跑的 periodic Timer,理由同上一則測試。
  });

  testWidgets('adjust:調到 0 時停止計時器', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(restTimerControllerProvider.notifier);

    notifier.start(seconds: 10);
    notifier.adjust(-10);

    expect(container.read(restTimerControllerProvider).remainingSeconds, 0);
    expect(container.read(restTimerControllerProvider).isRunning, isFalse);

    // 已停止,pump 不應該再有任何變化或拋錯。
    await tester.pump(const Duration(seconds: 2));
    expect(container.read(restTimerControllerProvider).remainingSeconds, 0);
  });

  testWidgets('skip:立即清空回到未啟動狀態', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(restTimerControllerProvider.notifier);

    notifier.start(seconds: 90, exerciseName: '硬舉');
    notifier.skip();

    final state = container.read(restTimerControllerProvider);
    expect(state.remainingSeconds, 0);
    expect(state.totalSeconds, 0);
    expect(state.isRunning, isFalse);
    expect(state.isVisible, isFalse);

    // skip 後即使繼續 pump,也不該再有殘留的 timer 觸發任何變化。
    await tester.pump(const Duration(seconds: 5));
    expect(container.read(restTimerControllerProvider).remainingSeconds, 0);
  });

  testWidgets('seconds <= 0:不啟動計時器,直接停在 0', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(restTimerControllerProvider.notifier);

    notifier.start(seconds: 0, exerciseName: '暖身組不休息');

    final state = container.read(restTimerControllerProvider);
    expect(state.isRunning, isFalse);
    expect(state.isVisible, isFalse);
  });

  testWidgets('自然倒數結束才震動一次;跳過與手動調到 0 不震動', (tester) async {
    var feedbacks = 0;
    final container = ProviderContainer(
      overrides: [restTimerFinishedFeedbackProvider.overrideWithValue(() => feedbacks++)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(restTimerControllerProvider.notifier);

    notifier.start(seconds: 2);
    await tester.pump(const Duration(seconds: 3));
    expect(feedbacks, 1);

    notifier.start(seconds: 30);
    notifier.skip();
    await tester.pump(const Duration(seconds: 31));
    expect(feedbacks, 1);

    notifier.start(seconds: 15);
    notifier.adjust(-15);
    await tester.pump(const Duration(seconds: 16));
    expect(feedbacks, 1);
  });

  group('結束時間點與通知', () {
    testWidgets('start:先 cancel 再 schedule 到 now+seconds;重啟同樣先 cancel 再重排', (tester) async {
      final scheduler = FakeRestNotificationScheduler();
      final container = _containerWith(scheduler);
      var now = _t0;
      await withClock(Clock(() => now), () async {
        final notifier = container.read(restTimerControllerProvider.notifier);
        notifier.start(seconds: 90, exerciseName: '深蹲');
        expect(scheduler.calls, ['cancel', _sched(_t0.add(const Duration(seconds: 90)), '深蹲')]);

        scheduler.calls.clear();
        now = now.add(const Duration(seconds: 10));
        await tester.pump(const Duration(seconds: 10));
        notifier.start(seconds: 30, exerciseName: '硬舉');
        expect(scheduler.calls, ['cancel', _sched(now.add(const Duration(seconds: 30)), '硬舉')]);

        notifier.skip();
      });
    });

    testWidgets('adjust:改 endsAt 並重排到新時間;調到 0 取消通知', (tester) async {
      final scheduler = FakeRestNotificationScheduler();
      final container = _containerWith(scheduler);
      await withClock(Clock(() => _t0), () async {
        final notifier = container.read(restTimerControllerProvider.notifier);
        notifier.start(seconds: 30, exerciseName: '臥推');
        scheduler.calls.clear();

        notifier.adjust(15);
        expect(scheduler.calls, [_sched(_t0.add(const Duration(seconds: 45)), '臥推')]);
        expect(container.read(restTimerControllerProvider).remainingSeconds, 45);

        scheduler.calls.clear();
        notifier.adjust(-15);
        expect(scheduler.calls, [_sched(_t0.add(const Duration(seconds: 30)), '臥推')]);

        scheduler.calls.clear();
        notifier.adjust(-30);
        expect(scheduler.calls, ['cancel']);
        final state = container.read(restTimerControllerProvider);
        expect(state.isRunning, isFalse);
        expect(state.finishedCount, 0);
      });
    });

    testWidgets('skip、自然結束各取消一次;start(seconds: 0) 只取消不排程', (tester) async {
      final scheduler = FakeRestNotificationScheduler();
      final container = _containerWith(scheduler);
      var now = _t0;
      await withClock(Clock(() => now), () async {
        final notifier = container.read(restTimerControllerProvider.notifier);

        notifier.start(seconds: 30);
        scheduler.calls.clear();
        notifier.skip();
        expect(scheduler.calls, ['cancel']);

        scheduler.calls.clear();
        notifier.start(seconds: 0);
        expect(scheduler.calls, ['cancel']);

        notifier.start(seconds: 2);
        scheduler.calls.clear();
        now = now.add(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));
        expect(container.read(restTimerControllerProvider).finishedCount, 1);
        expect(scheduler.calls, ['cancel']);
      });
    });

    testWidgets('provider dispose:計時中取消通知;沒在計時不呼叫', (tester) async {
      final running = FakeRestNotificationScheduler();
      final c1 = ProviderContainer(overrides: [restNotificationSchedulerProvider.overrideWithValue(running)]);
      c1.read(restTimerControllerProvider.notifier).start(seconds: 60);
      running.calls.clear();
      c1.dispose();
      expect(running.calls, ['cancel']);

      final idle = FakeRestNotificationScheduler();
      final c2 = ProviderContainer(overrides: [restNotificationSchedulerProvider.overrideWithValue(idle)]);
      c2.read(restTimerControllerProvider.notifier);
      c2.dispose();
      expect(idle.calls, isEmpty);
    });
  });

  group('以時間點計算剩餘秒數(背景/鎖屏後回來)', () {
    testWidgets('Timer 沒觸發期間時鐘前進:下一個 tick 直接顯示正確剩餘秒數(進位)', (tester) async {
      final container = _containerWith(FakeRestNotificationScheduler());
      var now = _t0;
      await withClock(Clock(() => now), () async {
        final notifier = container.read(restTimerControllerProvider.notifier);
        notifier.start(seconds: 90);

        // 背景 40.5 秒:時鐘走了、Timer 一次都沒觸發。
        now = now.add(const Duration(milliseconds: 40500));
        expect(container.read(restTimerControllerProvider).remainingSeconds, 90);

        await tester.pump(const Duration(seconds: 1));
        // endsAt - now = 49.5 秒 → 進位 50。
        expect(container.read(restTimerControllerProvider).remainingSeconds, 50);
        expect(container.read(restTimerControllerProvider).finishedCount, 0);

        notifier.skip();
      });
    });

    testWidgets('App 在背景時自然結束:不取消通知(讓它送達),計時照常結束', (tester) async {
      var feedbacks = 0;
      final scheduler = FakeRestNotificationScheduler();
      final container = _containerWith(scheduler, feedback: () => feedbacks++, inForeground: () => false);
      var now = _t0;
      await withClock(Clock(() => now), () async {
        container.read(restTimerControllerProvider.notifier).start(seconds: 60, exerciseName: '划船');
        scheduler.calls.clear();

        now = now.add(const Duration(seconds: 61));
        await tester.pump(const Duration(seconds: 1));

        final state = container.read(restTimerControllerProvider);
        expect(state.isRunning, isFalse);
        expect(state.finishedCount, 1);
        expect(feedbacks, 1);
        expect(scheduler.calls, isEmpty);
      });
    });

    testWidgets('背景期間已超過 endsAt:下一個 tick 自然結束一次,震動一次,之後不再觸發', (tester) async {
      var feedbacks = 0;
      final scheduler = FakeRestNotificationScheduler();
      final container = _containerWith(scheduler, feedback: () => feedbacks++);
      var now = _t0;
      await withClock(Clock(() => now), () async {
        final notifier = container.read(restTimerControllerProvider.notifier);
        notifier.start(seconds: 60, exerciseName: '划船');
        scheduler.calls.clear();

        now = now.add(const Duration(minutes: 10));
        await tester.pump(const Duration(seconds: 1));

        final state = container.read(restTimerControllerProvider);
        expect(state.remainingSeconds, 0);
        expect(state.isRunning, isFalse);
        expect(state.finishedCount, 1);
        expect(feedbacks, 1);
        expect(scheduler.calls, ['cancel']);

        now = now.add(const Duration(minutes: 1));
        await tester.pump(const Duration(seconds: 5));
        expect(container.read(restTimerControllerProvider).finishedCount, 1);
        expect(feedbacks, 1);
      });
    });

    testWidgets('adjust 以目前剩餘時間為基準(背景後再調整)', (tester) async {
      final container = _containerWith(FakeRestNotificationScheduler());
      var now = _t0;
      await withClock(Clock(() => now), () async {
        final notifier = container.read(restTimerControllerProvider.notifier);
        notifier.start(seconds: 60);
        now = now.add(const Duration(seconds: 50));
        notifier.adjust(15);
        // endsAt = start+75s,現在 start+50s → 剩 25。
        expect(container.read(restTimerControllerProvider).remainingSeconds, 25);
        notifier.adjust(-30);
        expect(container.read(restTimerControllerProvider).isRunning, isFalse);
      });
    });
  });

  group('通知失敗不影響計時', () {
    for (final mode in ['sync', 'async']) {
      testWidgets('scheduler $mode 拋例外:start/adjust/skip/自然結束照常', (tester) async {
        var feedbacks = 0;
        final scheduler = FakeRestNotificationScheduler(throwSync: mode == 'sync', throwAsync: mode == 'async');
        final container = _containerWith(scheduler, feedback: () => feedbacks++);
        final notifier = container.read(restTimerControllerProvider.notifier);

        notifier.start(seconds: 5);
        expect(container.read(restTimerControllerProvider).isRunning, isTrue);
        notifier.adjust(-2);
        expect(container.read(restTimerControllerProvider).remainingSeconds, 3);

        await tester.pump(const Duration(seconds: 3));
        expect(container.read(restTimerControllerProvider).finishedCount, 1);
        expect(feedbacks, 1);

        notifier.start(seconds: 10);
        notifier.skip();
        expect(container.read(restTimerControllerProvider).isRunning, isFalse);
        // 讓非同步錯誤有機會浮現——被吃掉才不會讓測試以 uncaught async error 失敗。
        await tester.pump();
      });
    }
  });

  group('真實 scheduler(測試環境無 plugin)', () {
    test('schedule/cancel 不拋例外', () async {
      final scheduler = LocalRestNotificationScheduler();
      await scheduler.cancel();
      await scheduler.schedule(DateTime.now().add(const Duration(seconds: 5)), exerciseName: '深蹲');
      await scheduler.cancel();
    });

    test('通知文案', () {
      expect(restNotificationBody('深蹲'), '準備好進行下一組 深蹲 了嗎?');
      expect(restNotificationBody(null), '準備好進行下一組了嗎?');
    });
  });
}
