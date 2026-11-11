/// Supabase 連線設定與初始化(寫法對齊 ~/Documents/self/accounting 的
/// `lib/data/supabase_client.dart`)。
///
/// 環境切換全靠 `--dart-define`:
/// - `SUPABASE_URL`/`SUPABASE_ANON_KEY`:雲端專案位址與**公開** anon/publishable
///   金鑰。service_role 之類的祕密金鑰不進程式碼。
/// - `USE_MOCK=true`:完全不連網,不初始化 Supabase,資料層走本機 Drift
///   (`Drift*Repository`,與 `flutter test` 走的是同一套實作)。
///
/// 資料層切換點是 [supabaseClientProvider]:預設 null = 走 Drift;`main.dart`
/// 只在「非 USE_MOCK 且 URL/金鑰都有給」時初始化 Supabase 並 override 成
/// `Supabase.instance.client`,repository providers(`providers.dart`)看到非 null
/// 就改走 `Supabase*Repository`。
library;

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'secure_session_storage.dart';

// debug/profile 的 defaultValue 是雲端 workout-dev 專案的位址與 **publishable**
// key——本來就會打包進 App 的公開資訊,可進版控(同 accounting);權限由 RLS
// 把關。要連別的專案用 --dart-define 覆寫;純本機帶 USE_MOCK=true。
// release build **沒有預設值**:漏帶 define 時不可默默連 dev(畢業總審 B1——
// 真實用戶的舊歷史會被傳到 dev,改發 prod 版後還會撞 owner conflict 而清掉
// 本機資料)。release 一律用 `tool/build_ios_prod.sh` 打包;設定不齊時 main.dart
// 顯示錯誤畫面,不啟動資料層。
const kSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: kReleaseMode ? '' : 'https://imudkbxvkefzafptqhae.supabase.co',
);

const kSupabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: kReleaseMode ? '' : 'sb_publishable_oAQnLRCuCjxS7fLAArEoxw_S-WKUK4h',
);

/// 純本機模式:不初始化 Supabase,資料層維持 Drift。
const kUseMock = bool.fromEnvironment('USE_MOCK');

/// URL 與金鑰是否都有給。
const kSupabaseConfigured = kSupabaseUrl != '' && kSupabaseAnonKey != '';

/// 是否要連 Supabase:非 USE_MOCK 且設定齊全。
const kUseSupabase = !kUseMock && kSupabaseConfigured;

/// release build 既非 USE_MOCK 又沒帶 Supabase 設定 = 打包流程漏帶 define。
/// main.dart 遇到時只顯示錯誤畫面,不跑匯入、不啟動資料層。
const kReleaseMisconfigured = kReleaseMode && !kUseMock && !kSupabaseConfigured;

/// 組 Supabase auth 選項:session 改存 Keychain/Keystore(見
/// `secure_session_storage.dart`);Web 的 localStorage 為 null,沿用套件預設。
/// 其餘 auth 選項維持套件預設值,只換 localStorage。抽成函式是為了能測「非 Web 時
/// 真的接上 SecureSessionStorage」,免得有人改動時悄悄退回明文儲存。
FlutterAuthClientOptions buildAuthOptions({required String supabaseUrl, bool? isWeb}) {
  return FlutterAuthClientOptions(localStorage: createSessionLocalStorage(supabaseUrl: supabaseUrl, isWeb: isWeb));
}

Future<void> initSupabase() {
  return Supabase.initialize(
    url: kSupabaseUrl,
    publishableKey: kSupabaseAnonKey,
    authOptions: buildAuthOptions(supabaseUrl: kSupabaseUrl),
  );
}

/// 由 `main.dart` override 成 `Supabase.instance.client`;預設 null = 沒有連線
/// (測試/USE_MOCK/未設定),repository 走 Drift。
final supabaseClientProvider = Provider<SupabaseClient?>((ref) => null);
