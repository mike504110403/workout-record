// `rest_notification_scheduler.dart` 的環境偵測(有 dart:io 的平台):
// `flutter test` 會在測試行程的環境變數放 `FLUTTER_TEST`。
import 'dart:io' show Platform;

bool get isFlutterTestEnvironment => Platform.environment.containsKey('FLUTTER_TEST');
