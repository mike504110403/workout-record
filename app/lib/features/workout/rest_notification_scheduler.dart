// 組間休息結束的本機通知。`RestTimerController` 只依賴 [RestNotificationScheduler]
// 介面;真實實作用 `flutter_local_notifications` 的 `zonedSchedule`,讓鎖螢幕/
// App 進背景時休息結束仍會提醒。
//
// 設計重點:
// - 全程只會有一則休息通知([restNotificationId] 固定),排程同 id 即覆蓋。
// - plugin 初始化與權限請求延後到「第一次 schedule」才做,App 啟動不會跳權限框。
// - 任何 plugin 例外/權限被拒都在這裡吃掉(`debugPrint`),不得影響計時。
// - 所有操作串成一條佇列,避免 cancel/schedule 因為非同步交錯而亂序。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import 'rest_notification_env_stub.dart' if (dart.library.io) 'rest_notification_env_io.dart';

abstract class RestNotificationScheduler {
  /// 在 [at] 排一則「休息結束」通知(取代既有的休息通知)。
  Future<void> schedule(DateTime at, {String? exerciseName});

  /// 取消尚未觸發的休息通知(沒有排程時為 no-op)。
  Future<void> cancel();
}

/// Web 與測試環境用:什麼都不做。
class NoopRestNotificationScheduler implements RestNotificationScheduler {
  const NoopRestNotificationScheduler();

  @override
  Future<void> schedule(DateTime at, {String? exerciseName}) async {}

  @override
  Future<void> cancel() async {}
}

/// 休息通知固定的 id(全程至多一則)。
const int restNotificationId = 7101;

const String restNotificationTitle = '休息結束';

String restNotificationBody(String? exerciseName) =>
    exerciseName != null ? '準備好進行下一組 $exerciseName 了嗎?' : '準備好進行下一組了嗎?';

class LocalRestNotificationScheduler implements RestNotificationScheduler {
  LocalRestNotificationScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void> _tail = Future<void>.value();
  bool _initialized = false;

  /// 本次執行期間使用者已拒絕過權限:不再重複跳權限框(靜默降級)。
  bool _permissionDenied = false;

  @override
  Future<void> schedule(DateTime at, {String? exerciseName}) => _enqueue(() => _schedule(at, exerciseName));

  @override
  Future<void> cancel() => _enqueue(_cancel);

  Future<void> _enqueue(Future<void> Function() op) {
    final next = _tail.then((_) => op()).catchError((Object e, StackTrace s) {
      debugPrint('RestNotificationScheduler: $e');
    });
    _tail = next;
    return next;
  }

  Future<void> _schedule(DateTime at, String? exerciseName) async {
    if (!await _ensureReady()) return;
    if (!await _ensurePermission()) return;
    await _plugin.zonedSchedule(
      id: restNotificationId,
      title: restNotificationTitle,
      body: restNotificationBody(exerciseName),
      // 只用 UTC 瞬間,不需要時區資料庫與在地時區查詢。
      scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'rest_timer',
          '休息計時',
          channelDescription: '組間休息結束提醒',
          importance: Importance.high,
          priority: Priority.high,
        ),
        // 前景時不顯示系統橫幅(前景由畫面內提示處理);背景/鎖屏仍有聲音。
        iOS: DarwinNotificationDetails(
          presentAlert: false,
          presentBanner: false,
          presentList: false,
          presentBadge: false,
          presentSound: true,
        ),
      ),
      // inexact:不需要申請 exact alarm 權限。
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> _cancel() async {
    // 從沒排過就沒有東西可取消,也不該為了取消去初始化 plugin。
    if (!_initialized) return;
    await _plugin.cancel(id: restNotificationId);
  }

  Future<bool> _ensureReady() async {
    if (_initialized) return true;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // 權限延後到第一次排程才問,初始化時一律不請求。
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialized = true;
    return true;
  }

  /// 回傳是否可以排通知;被拒絕時靜默回 false(計時照常,只是沒通知)。
  Future<bool> _ensurePermission() async {
    if (_permissionDenied) return false;
    final granted = await _requestPermission();
    if (!granted) _permissionDenied = true;
    return granted;
  }

  Future<bool> _requestPermission() async {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        return await ios?.requestPermissions(alert: true, sound: true) ?? false;
      case TargetPlatform.android:
        final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        if (android == null) return false;
        if (await android.areNotificationsEnabled() ?? false) return true;
        return await android.requestNotificationsPermission() ?? false;
      default:
        return false;
    }
  }
}

final restNotificationSchedulerProvider = Provider<RestNotificationScheduler>((ref) {
  if (kIsWeb || isFlutterTestEnvironment) {
    return const NoopRestNotificationScheduler();
  }
  return LocalRestNotificationScheduler();
});
