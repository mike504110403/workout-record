// 組間休息倒數計時。對照 iOS `RestTimerView.swift` 的 `RestTimerManager`
// (`ios/WorkoutRecord/WorkoutRecord/Sources/Views/Workout/RestTimerView.swift:151-216`)
// ——同樣的 setup/start/adjustTime/stop 語意,搬成 Riverpod `Notifier` +
// `Timer.periodic`(不是 iOS 的 `Timer.scheduledTimer` + Combine,但每秒遞減
// 一次的行為一致)。
//
// 剩餘秒數以「結束時間點 - 現在」計算(時間來源 `package:clock`),Timer 只負責
// 每秒驅動畫面;休息開始時另外排一則本機通知(`RestNotificationScheduler`),
// 鎖屏/進背景也準時提醒。
//
// 測試用 `tester.pump(Duration(seconds: n))` 推進虛擬時間即可觸發
// `Timer.periodic` 的回呼(flutter_test 的 `AutomatedTestWidgetsFlutterBinding`
// 在 `FakeAsync` zone 內跑測試本體,`clock.now()` 與 `Timer` 會一起被推進)。
// 模擬「背景後時間跳過」則用 `withClock` 在 Timer 不觸發的情況下推進時鐘。
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'rest_notification_scheduler.dart';

/// 休息自然倒數結束時的震動(對照 iOS `RestTimerView.swift` 結束時的
/// `UINotificationFeedbackGenerator`)。抽成 provider 讓測試可觀察;使用者
/// 手動 ±15 秒調到 0 或跳過不震動。Web/桌面平台 HapticFeedback 為 no-op。
final restTimerFinishedFeedbackProvider = Provider<void Function()>(
  (ref) =>
      () => unawaited(HapticFeedback.heavyImpact()),
);

/// App 目前是否在前景。休息自然結束時只有前景才取消通知——背景中
/// (Android 行程活著時 Dart Timer 照跑)若也取消,會把正要送達或剛送達的
/// 休息通知刪掉,鎖螢幕提醒就失效。抽成 provider 讓測試可模擬背景。
/// lifecycleState 為 null(尚未回報,例如測試環境)視為前景。
final restTimerAppInForegroundProvider = Provider<bool Function()>(
  (ref) => () {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle == null || lifecycle == AppLifecycleState.resumed;
  },
);

class RestTimerState {
  const RestTimerState({
    this.totalSeconds = 0,
    this.remainingSeconds = 0,
    this.isRunning = false,
    this.exerciseName,
    this.finishedCount = 0,
  });

  /// 自然倒數結束的累計次數(手動調到 0、跳過不算)。畫面 listen 這個值的
  /// 變化跳「休息時間結束」提示(對照 iOS `WorkoutView.swift:77` 的 alert)。
  final int finishedCount;

  final int totalSeconds;
  final int remainingSeconds;
  final bool isRunning;
  final String? exerciseName;

  /// 0.0 ~ 1.0,給進度環用。[totalSeconds] 為 0(未啟動)時回傳 0。
  double get progress => totalSeconds == 0 ? 0 : remainingSeconds / totalSeconds;

  /// 計時器目前是否顯示中(對照 iOS `RestTimerHeaderView` 只在
  /// `timerManager.isRunning` 時顯示——這裡額外把「剛好倒數到 0 但畫面還沒
  /// 被下一次操作清掉」也視為不顯示,`remainingSeconds > 0` 更貼近使用者
  /// 觀感)。
  bool get isVisible => isRunning && remainingSeconds > 0;

  RestTimerState copyWith({
    int? totalSeconds,
    int? remainingSeconds,
    bool? isRunning,
    String? exerciseName,
    int? finishedCount,
  }) {
    return RestTimerState(
      totalSeconds: totalSeconds ?? this.totalSeconds,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      isRunning: isRunning ?? this.isRunning,
      exerciseName: exerciseName ?? this.exerciseName,
      finishedCount: finishedCount ?? this.finishedCount,
    );
  }
}

class RestTimerController extends Notifier<RestTimerState> {
  Timer? _timer;

  /// 休息結束的時間點。剩餘秒數一律用 `_endsAt - clock.now()` 算,不靠 tick
  /// 次數遞減——App 進背景/鎖屏時 Timer 會被凍結,回前景的第一個 tick 就能
  /// 顯示正確秒數(或直接走自然結束)。非 null = 計時進行中。
  DateTime? _endsAt;

  late RestNotificationScheduler _scheduler;

  @override
  RestTimerState build() {
    // dispose 回呼裡不能再用 ref,先把 scheduler 抓起來。
    _scheduler = ref.read(restNotificationSchedulerProvider);
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
      // 帳號登出/訓練結束讓 provider 被丟棄時,不得留下孤兒通知。
      if (_endsAt != null) {
        _endsAt = null;
        _safely(_scheduler.cancel);
      }
    });
    return const RestTimerState();
  }

  /// 開始(或重啟)倒數計時。對照 D 規格「儲存組後自動啟動組間休息倒數」+
  /// 矩陣「休息計時中儲存下一組 → 重啟計時器」——呼叫這個方法一律先取消
  /// 既有計時器再重新起算,不用另外判斷「目前是否正在跑」,天生涵蓋重啟
  /// 情境。[seconds] <= 0(使用者把休息時間調到 0)視同不需要休息,直接
  /// 停在 0、不啟動計時器。
  void start({required int seconds, String? exerciseName}) {
    _timer?.cancel();
    _timer = null;
    _safely(_scheduler.cancel);

    if (seconds <= 0) {
      _endsAt = null;
      state = RestTimerState(exerciseName: exerciseName, finishedCount: state.finishedCount);
      return;
    }

    final endsAt = clock.now().add(Duration(seconds: seconds));
    _endsAt = endsAt;
    state = RestTimerState(
      totalSeconds: seconds,
      remainingSeconds: seconds,
      isRunning: true,
      exerciseName: exerciseName,
      finishedCount: state.finishedCount,
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _safely(() => _scheduler.schedule(endsAt, exerciseName: exerciseName));
  }

  /// `endsAt - now`,無條件進位到整秒;已到或超過回傳 0。
  static int _secondsUntil(DateTime endsAt, DateTime now) {
    final micros = endsAt.difference(now).inMicroseconds;
    if (micros <= 0) return 0;
    return (micros + Duration.microsecondsPerSecond - 1) ~/ Duration.microsecondsPerSecond;
  }

  void _tick() {
    final endsAt = _endsAt;
    if (endsAt == null) return;
    final remaining = _secondsUntil(endsAt, clock.now());
    if (remaining <= 0) {
      _timer?.cancel();
      _timer = null;
      _endsAt = null;
      state = state.copyWith(remainingSeconds: 0, isRunning: false, finishedCount: state.finishedCount + 1);
      if (ref.read(restTimerAppInForegroundProvider)()) _safely(_scheduler.cancel);
      ref.read(restTimerFinishedFeedbackProvider)();
      return;
    }
    state = state.copyWith(remainingSeconds: remaining);
  }

  /// ±15 秒調整(對照 iOS `RestTimerManager.adjustTime`):改的是結束時間點,
  /// 並把通知重排到新的時間。往下調整不會低於 0;若把時間往上調超過原本的
  /// [RestTimerState.totalSeconds],連帶把 `totalSeconds` 也拉高——否則進度環的
  /// `progress`(= remaining / total)會超過 1.0。調到 0 時等同時間到,停止
  /// 計時器並取消通知。沒有進行中的計時時不做事。
  void adjust(int deltaSeconds) {
    final endsAt = _endsAt;
    if (endsAt == null || state.totalSeconds == 0) return;
    final newEndsAt = endsAt.add(Duration(seconds: deltaSeconds));
    final newRemaining = _secondsUntil(newEndsAt, clock.now());

    if (newRemaining == 0) {
      _timer?.cancel();
      _timer = null;
      _endsAt = null;
      state = state.copyWith(remainingSeconds: 0, isRunning: false);
      _safely(_scheduler.cancel);
      return;
    }

    _endsAt = newEndsAt;
    final newTotal = newRemaining > state.totalSeconds ? newRemaining : state.totalSeconds;
    state = state.copyWith(remainingSeconds: newRemaining, totalSeconds: newTotal);
    final name = state.exerciseName;
    _safely(() => _scheduler.schedule(newEndsAt, exerciseName: name));
  }

  /// 跳過休息,直接清空回到未啟動狀態。
  void skip() {
    _timer?.cancel();
    _timer = null;
    _endsAt = null;
    state = RestTimerState(finishedCount: state.finishedCount);
    _safely(_scheduler.cancel);
  }

  /// 通知是附加功能:scheduler 同步或非同步拋例外都只記 log,不得影響計時。
  void _safely(Future<void> Function() op) {
    try {
      unawaited(
        op().catchError((Object e, StackTrace s) {
          debugPrint('RestTimerController: notification failed: $e');
        }),
      );
    } catch (e) {
      debugPrint('RestTimerController: notification failed: $e');
    }
  }
}

final restTimerControllerProvider = NotifierProvider<RestTimerController, RestTimerState>(RestTimerController.new);
