// 匯入(CoreData / legacy prefs)成功 / 失敗紀錄的本地純文字 log,對應
// docs/COREDATA_MIGRATION_SPEC.md 4.6 節「不要只靠 debugPrint(release build
// 抓不到)」的要求。
//
// 存放位置:path_provider 的 app support 目錄下的 `logs/import.log`,純文字
// 逐行追加,不做輪替/清理(個人健身紀錄 App 的匯入只在首啟跑一輪,行數
// 天花板很低,不需要複雜的 log rotation)。
//
// 平台防護:web 平台天生不會走到會呼叫這裡的路徑(CoreDataImporter 在 web
// 用 no-op stub;LegacyPrefsImporter 先擋 Platform.isIOS),但這裡仍用
// [kIsWeb] 提早 return——dart:io 在 Flutter web 上編譯得過(相容 shim),
// 但實際的檔案 I/O 在執行期會丟 UnsupportedError,多一層防護避免未來新增
// 呼叫路徑時意外踩雷。
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImportLog {
  /// [supportDirectoryProvider] 預設是 path_provider 的真正實作;測試時可
  /// 換成回傳臨時目錄的函式,跟 [CoreDataImporter] 的建構子是同一套模式,
  /// 不需要 mock 任何 platform channel。
  const ImportLog({
    Future<Directory> Function() supportDirectoryProvider =
        getApplicationSupportDirectory,
  }) : _supportDirectoryProvider = supportDirectoryProvider;

  final Future<Directory> Function() _supportDirectoryProvider;

  static const _dirName = 'logs';
  static const _fileName = 'import.log';

  /// 追加一行 log(自動加時間戳)。log 寫入本身失敗(例如磁碟空間不足)
  /// 不能影響匯入流程的成功/失敗判定——log 只是輔助 debug 用的旁路,忽略
  /// 例外即可。
  Future<void> append(String message) async {
    if (kIsWeb) return;
    try {
      final supportDir = await _supportDirectoryProvider();
      final logDir = Directory(p.join(supportDir.path, _dirName));
      if (!logDir.existsSync()) {
        logDir.createSync(recursive: true);
      }
      final file = File(p.join(logDir.path, _fileName));
      final timestamp = DateTime.now().toIso8601String();
      await file.writeAsString(
        '[$timestamp] $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // 忽略——見上方方法註解。
    }
  }
}
