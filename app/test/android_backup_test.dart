// Android 關備份:資料在 Supabase,session 在安全儲存;若讓系統把 App 私有資料
// (含本機 Drift 資料庫、SharedPreferences)自動備份到 Google 雲端或裝置間遷移,
// 隱私政策「不會上傳到我們的伺服器」的陳述就不成立,也可能把他人帳號的本機資料還原到新裝置。
//
// 兩套機制要各自擋:`allowBackup="false"` 在 Android 11 以下關掉整個備份;Android 12+
// 以 `dataExtractionRules`(雲端備份與裝置對裝置遷移)為準,不能只靠 allowBackup 一個屬性,
// 所以另外宣告規則檔把所有 domain 排除。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _application() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  return RegExp(r'<application\b[^>]*>').firstMatch(manifest)!.group(0)!;
}

void main() {
  test('AndroidManifest <application> 關閉 allowBackup 與 fullBackupContent', () {
    final application = _application();
    expect(application, contains('android:allowBackup="false"'));
    expect(application, contains('android:fullBackupContent="false"'));
  });

  test('AndroidManifest <application> 指向 Android 12+ 的 dataExtractionRules', () {
    expect(_application(), contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
  });

  test('data_extraction_rules.xml:雲端備份與裝置遷移都排除 root/file/database/sharedpref', () {
    final xml =
        File('android/app/src/main/res/xml/data_extraction_rules.xml').readAsStringSync();
    for (final section in ['cloud-backup', 'device-transfer']) {
      final block = RegExp('<$section[^>]*>(.*?)</$section>', dotAll: true).firstMatch(xml);
      expect(block, isNotNull, reason: '缺 <$section>');
      for (final domain in ['root', 'file', 'database', 'sharedpref']) {
        expect(
          RegExp('<exclude\\s+domain="$domain"\\s+path="\\."\\s*/>').hasMatch(block!.group(1)!),
          isTrue,
          reason: '<$section> 未排除 $domain',
        );
      }
    }
  });
}
