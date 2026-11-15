import 'package:workout_record/features/workout/rest_notification_scheduler.dart';

/// 記錄呼叫序列的假 scheduler;可指定同步/非同步拋例外,驗證計時不受通知失敗影響。
class FakeRestNotificationScheduler implements RestNotificationScheduler {
  FakeRestNotificationScheduler({this.throwSync = false, this.throwAsync = false});

  final bool throwSync;
  final bool throwAsync;
  final calls = <String>[];

  @override
  Future<void> schedule(DateTime at, {String? exerciseName}) {
    calls.add('schedule(${at.toIso8601String()},$exerciseName)');
    if (throwSync) throw StateError('sync boom');
    if (throwAsync) return Future.error(StateError('async boom'));
    return Future.value();
  }

  @override
  Future<void> cancel() {
    calls.add('cancel');
    if (throwSync) throw StateError('sync boom');
    if (throwAsync) return Future.error(StateError('async boom'));
    return Future.value();
  }
}
