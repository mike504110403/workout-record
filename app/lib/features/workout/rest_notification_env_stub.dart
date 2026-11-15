// `rest_notification_scheduler.dart` 的環境偵測(無 dart:io 平台,即 Web):
// 永遠不是 flutter test 環境。
bool get isFlutterTestEnvironment => false;
