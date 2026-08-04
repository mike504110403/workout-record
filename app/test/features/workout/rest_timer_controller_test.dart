// RestTimerController 計時器測試:用 `tester.pump(Duration)` 控制虛擬時間
// (flutter_test 的 AutomatedTestWidgetsFlutterBinding 在 FakeAsync zone 內跑
// 測試本體,`Timer.periodic` 天生能被 pump 推進,不需要真的等待)。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_record/features/workout/rest_timer_controller.dart';

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
}
