import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 舊 CoreData 檔名(跟 coredata_importer_io.dart 的 `_oldDbFileName` 同值,位置同在
/// Application Support 目錄)。
const kLegacyCoreDataDbFileName = 'WorkoutRecord.sqlite';

class LegacyCoreDataFiles {
  /// [supportDirPathProvider] 預設是 path_provider 的 Application Support 目錄;
  /// 測試換成暫存目錄。
  const LegacyCoreDataFiles({Future<String> Function()? supportDirPathProvider})
      : _supportDirPathProvider = supportDirPathProvider;

  final Future<String> Function()? _supportDirPathProvider;

  Future<String?> _dirPath() async {
    try {
      return await (_supportDirPathProvider?.call() ??
          getApplicationSupportDirectory().then((d) => d.path));
    } catch (_) {
      return null;
    }
  }

  /// 舊 SQLite 主檔是否還在。匯入完成或失敗都不會刪它,所以「在」代表這台裝置
  /// 上還留著舊 iOS 的資料(不論有沒有匯入成功)。查不到目錄或例外一律回 false。
  Future<bool> exists() async {
    final dirPath = await _dirPath();
    if (dirPath == null) return false;
    try {
      return File(p.join(dirPath, kLegacyCoreDataDbFileName)).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// 刪除舊 SQLite 主檔與 `-wal`、`-shm`(WAL 模式下資料可能還躺在 -wal 裡,
  /// 只刪主檔會留下殘片)。盡力而為:單檔刪除失敗不拋、不影響其他檔。
  /// 回傳實際刪掉的檔案數。
  Future<int> deleteAll() async {
    final dirPath = await _dirPath();
    if (dirPath == null) return 0;
    var deleted = 0;
    for (final suffix in const ['', '-wal', '-shm']) {
      final file = File(p.join(dirPath, '$kLegacyCoreDataDbFileName$suffix'));
      try {
        if (file.existsSync()) {
          await file.delete();
          deleted++;
        }
      } catch (_) {
        // 刪不掉(權限/檔案被占用)不阻擋其他檔與呼叫端。
      }
    }
    return deleted;
  }
}
