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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// TODO(Mike): 雲端專案的 URL 與公開 anon key 確定後可填進 defaultValue
// (公開資訊,可進版控,同 accounting);目前留空,未帶 dart-define 時
// [kSupabaseConfigured] 為 false,main.dart 會退回本機 Drift 並印警告。
const kSupabaseUrl = String.fromEnvironment('SUPABASE_URL');

const kSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// 純本機模式:不初始化 Supabase,資料層維持 Drift。
const kUseMock = bool.fromEnvironment('USE_MOCK');

/// URL 與金鑰是否都有給。
const kSupabaseConfigured = kSupabaseUrl != '' && kSupabaseAnonKey != '';

/// 是否要連 Supabase:非 USE_MOCK 且設定齊全。
const kUseSupabase = !kUseMock && kSupabaseConfigured;

Future<void> initSupabase() =>
    Supabase.initialize(url: kSupabaseUrl, publishableKey: kSupabaseAnonKey);

/// 由 `main.dart` override 成 `Supabase.instance.client`;預設 null = 沒有連線
/// (測試/USE_MOCK/未設定),repository 走 Drift。
final supabaseClientProvider = Provider<SupabaseClient?>((ref) => null);
