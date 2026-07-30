// spec 4.6 節「連續失敗達重試上限後,提供一個手動重試按鈕」的 UI。
//
// 只在 CoreData 匯入已標記 kCoreDataImportFailedPermanentlyKey 時渲染;
// 點擊後清掉旗標與連續失敗計數,重新呼叫 CoreDataImporter.importIfNeeded,
// 以 SnackBar 顯示成功/失敗結果。
//
// 自足 widget:預設讀真正的 SharedPreferences + 目前 ProviderScope 的
// AppDatabase,但 [checkPermanentlyFailed] / [importAction] 兩個建構子參數
// 可覆寫,widget test 因此不需要 mock SharedPreferences 或搭一整棵
// provider tree,直接注入假的檢查/重試函式即可(見
// app/test/migration/import_retry_tile_test.dart)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/migration/coredata_importer.dart';
import '../../../data/providers.dart';

class ImportRetryTile extends ConsumerStatefulWidget {
  const ImportRetryTile({
    super.key,
    this.checkPermanentlyFailed,
    this.importAction,
  });

  /// 是否顯示這個 tile(true = 曾連續失敗達上限)。預設讀
  /// [kCoreDataImportFailedPermanentlyKey]。
  final Future<bool> Function()? checkPermanentlyFailed;

  /// 點擊重試時實際執行的匯入動作。預設呼叫
  /// `const CoreDataImporter().importIfNeeded(db)`(db 來自
  /// [appDatabaseProvider])。呼叫前旗標與連續失敗計數已被清掉。
  ///
  /// 刻意不帶 AppDatabase 參數:注入假的 importAction 時完全不需要真正
  /// 開一個 Drift 資料庫連線(widget test 不該因為這裡而意外開檔)。
  final Future<ImportResult> Function()? importAction;

  @override
  ConsumerState<ImportRetryTile> createState() => _ImportRetryTileState();
}

class _ImportRetryTileState extends ConsumerState<ImportRetryTile> {
  late Future<bool> _visibleFuture;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _visibleFuture = _checkVisible();
  }

  Future<bool> _checkVisible() {
    final check = widget.checkPermanentlyFailed;
    if (check != null) {
      return check();
    }
    return _defaultCheckPermanentlyFailed();
  }

  Future<bool> _defaultCheckPermanentlyFailed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kCoreDataImportFailedPermanentlyKey) ?? false;
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);

    ImportResult result;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kCoreDataImportFailedPermanentlyKey, false);
      await prefs.setInt(kCoreDataImportAttemptsKey, 0);

      final action = widget.importAction;
      result = action != null
          ? await action()
          : await const CoreDataImporter()
              .importIfNeeded(ref.read(appDatabaseProvider));
    } catch (e) {
      result = ImportResult(success: false, skipped: false, errorMessage: '$e');
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success ? '舊資料重新匯入成功' : '重新匯入仍失敗:${result.errorMessage ?? '未知錯誤'}',
        ),
      ),
    );
    setState(() {
      _retrying = false;
      _visibleFuture = _checkVisible();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _visibleFuture,
      builder: (context, snapshot) {
        if (snapshot.data != true) {
          return const SizedBox.shrink();
        }
        return ListTile(
          leading: const Icon(Icons.warning_amber_rounded),
          title: const Text('舊資料匯入失敗'),
          subtitle: const Text('多次自動匯入失敗,可手動重試'),
          trailing: _retrying
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
                  onPressed: _retry,
                  child: const Text('重新匯入舊資料'),
                ),
        );
      },
    );
  }
}
