// LocalRestNotificationScheduler:用 MethodChannel 假 plugin 驗證
// - 權限框卡住時呼叫 cancel,最後不得留下排程(佇列保序);
// - 權限被拒時靜默不排程;
// - plugin 任何錯誤(含 TypeError)都被吃掉。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_record/features/workout/rest_notification_scheduler.dart';

const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> calls;
  late Completer<bool?> permission;
  late bool notificationsEnabled;
  late Object? Function(MethodCall call)? onZoned;
  late Object? initResult;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls = [];
    permission = Completer<bool?>();
    notificationsEnabled = false;
    onZoned = null;
    initResult = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'initialize':
          return initResult;
        case 'areNotificationsEnabled':
          return notificationsEnabled;
        case 'requestNotificationsPermission':
          return permission.future;
        case 'zonedSchedule':
          return onZoned?.call(call);
      }
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  DateTime soon() => DateTime.now().add(const Duration(minutes: 1));

  test('排程卡在權限框時 cancel:授權後先排程、再被取消,最後不留排程', () async {
    final scheduler = LocalRestNotificationScheduler();
    final scheduled = scheduler.schedule(soon(), exerciseName: '深蹲');
    await pumpEventQueue();
    expect(calls, contains('requestNotificationsPermission'));

    final cancelled = scheduler.cancel();
    await pumpEventQueue();
    // cancel 排在佇列後面,權限框沒回之前不會先跑。
    expect(calls.contains('cancel'), isFalse);

    permission.complete(true);
    await scheduled;
    await cancelled;
    expect(calls.last, 'cancel');
    expect(calls.indexOf('zonedSchedule'), lessThan(calls.indexOf('cancel')));
  });

  test('權限被拒:靜默降級,不排程不拋錯', () async {
    final scheduler = LocalRestNotificationScheduler();
    permission.complete(false);
    await scheduler.schedule(soon());
    expect(calls, isNot(contains('zonedSchedule')));
  });

  test('已有通知權限:不再請求,直接排程', () async {
    notificationsEnabled = true;
    final scheduler = LocalRestNotificationScheduler();
    await scheduler.schedule(soon());
    expect(calls, isNot(contains('requestNotificationsPermission')));
    expect(calls, contains('zonedSchedule'));
  });

  test('plugin 拋 PlatformException 被吃掉,之後仍可排程', () async {
    notificationsEnabled = true;
    final scheduler = LocalRestNotificationScheduler();
    onZoned = (_) => throw PlatformException(code: 'boom');
    await scheduler.schedule(soon());
    await scheduler.schedule(soon());
    onZoned = null;
    calls.clear();
    await scheduler.schedule(soon());
    expect(calls, contains('zonedSchedule'));
  });

  test('plugin 內部 TypeError(initialize 回傳型別不符)也被吃掉', () async {
    initResult = 'not-a-bool';
    final scheduler = LocalRestNotificationScheduler();
    await scheduler.schedule(soon());
    expect(calls, isNot(contains('zonedSchedule')));
    // 沒初始化成功就沒有排程,cancel 也不會去打平台。
    await scheduler.cancel();
  });

  test('從沒排過就 cancel:不初始化 plugin、不呼叫平台', () async {
    final scheduler = LocalRestNotificationScheduler();
    await scheduler.cancel();
    expect(calls, isEmpty);
  });
}
