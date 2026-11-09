# data/repositories

資料存取層,提供給 `features/` 底下的 controller/provider 使用。

- 每個 `*_repository.dart` 內含**介面**(`abstract interface class XxxRepository`)
  與 **Drift 實作**(`DriftXxxRepository`,本機 SQLite;`USE_MOCK`、測試、未設定
  Supabase 時使用)。
- `supabase/` 底下是 **Supabase 實作**(`SupabaseXxxRepository`),共用轉換層在
  `supabase/supabase_mapping.dart`;多步寫入走 Postgres function,定義在
  `supabase/migrations/20261110000300_rpc.sql`(repo 根目錄)。
- 實作切換在 `data/providers.dart`:`supabaseClientProvider` 非 null 就走 Supabase。
- 各方法語義以 Drift 實作的文件為準;Supabase 版的差異寫在各 `Supabase*` 類別文件。
