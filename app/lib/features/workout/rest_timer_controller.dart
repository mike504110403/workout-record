// 組間休息倒數計時。對照 iOS `RestTimerView.swift` 的 `RestTimerManager`
// (`ios/WorkoutRecord/WorkoutRecord/Sources/Views/Workout/RestTimerView.swift:151-216`)
// ——同樣的 setup/start/adjustTime/stop 語意,搬成 Riverpod `Notifier` +
// `Timer.periodic`(不是 iOS 的 `Timer.scheduledTimer` + Combine,但每秒遞減
// 一次的行為一致)。
//
// 測試用 `tester.pump(Duration(seconds: n))` 推進虛擬時間即可觸發
// `Timer.periodic` 的回呼(flutter_test 的 `AutomatedTestWidgetsFlutterBinding`
// 在 `FakeAsync` zone 內跑測試本體,`dart:async` 的 `Timer` 天生就能被
// `pump()` 推進,不需要額外的假時鐘依賴)。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class RestTimerState {
  const RestTimerState({
    this.totalSeconds = 0,
    this.remainingSeconds = 0,
    this.isRunning = false,
    this.exerciseName,
  });

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
  }) {
    return RestTimerState(
      totalSeconds: totalSeconds ?? this.totalSeconds,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      isRunning: isRunning ?? this.isRunning,
      exerciseName: exerciseName ?? this.exerciseName,
    );
  }
}

class RestTimerController extends Notifier<RestTimerState> {
  Timer? _timer;

  @override
  RestTimerState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
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

    if (seconds <= 0) {
      state = RestTimerState(exerciseName: exerciseName);
      return;
    }

    state = RestTimerState(
      totalSeconds: seconds,
      remainingSeconds: seconds,
      isRunning: true,
      exerciseName: exerciseName,
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (state.remainingSeconds <= 1) {
      _timer?.cancel();
      _timer = null;
      state = state.copyWith(remainingSeconds: 0, isRunning: false);
      return;
    }
    state = state.copyWith(remainingSeconds: state.remainingSeconds - 1);
  }

  /// ±15 秒調整(對照 iOS `RestTimerManager.adjustTime`)。往下調整不會低於
  /// 0;若把時間往上調超過原本的 [RestTimerState.totalSeconds],連帶把
  /// `totalSeconds` 也拉高——否則進度環的 `progress`(= remaining /
  /// total)會超過 1.0。調到 0 時等同時間到,停止計時器。
  void adjust(int deltaSeconds) {
    if (state.totalSeconds == 0) return;
    final newRemaining = (state.remainingSeconds + deltaSeconds).clamp(0, 1 << 30);
    final newTotal = newRemaining > state.totalSeconds ? newRemaining : state.totalSeconds;
    state = state.copyWith(remainingSeconds: newRemaining, totalSeconds: newTotal);

    if (newRemaining == 0) {
      _timer?.cancel();
      _timer = null;
      state = state.copyWith(isRunning: false);
    }
  }

  /// 跳過休息,直接清空回到未啟動狀態。
  void skip() {
    _timer?.cancel();
    _timer = null;
    state = const RestTimerState();
  }
}

final restTimerControllerProvider =
    NotifierProvider<RestTimerController, RestTimerState>(RestTimerController.new);
