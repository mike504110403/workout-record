// 本機 Drift(舊 CoreData 匯入的落點)→ Supabase 的一次性上傳介面。
//
// 現況(2026-11-10 改直連 Supabase 的資料層波):舊 iOS 版 CoreData 照舊在
// 首啟時匯入本機 Drift(main.dart 的 CoreDataImporter,不變);登入後把這份
// 本機資料一次性上傳到 Supabase 的流程**尚未實作**,這裡只先定介面。
//
// TODO(登入波): 實作 [LocalToCloudUploader]——
// - 觸發時機:登入成功、取得 auth uid 之後;以 SharedPreferences 旗標保證只跑一次,
//   失敗不寫旗標、下次登入重試(對齊 CoreDataImporter 的重試慣例)。
// - 擁有者改寫:本機列的 userId 是舊 Apple userIdentifier / 測試登入 id,上傳時
//   一律改寫成 auth uid(RLS 與 RPC 也會強制)。
// - 系統動作/系統模板不上傳(雲端已由 seed migration 提供,id 不同):本機
//   isSystem 動作的參照(workout_exercises/template_exercises/personal_records
//   的 exerciseId)要依「名稱 + categoryId」對應到雲端系統動作 id 再上傳。
// - 冪等:以本機 id 為主鍵 upsert,重跑不重複;子表先父後子。
// - 先確認雲端 schema 的 uuid 欄位能吃下本機所有 id(CoreData UUID 皆為標準格式)。
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/app_database.dart';

/// 一次性上傳的結果。
class CloudUploadResult {
  const CloudUploadResult({required this.success, this.uploadedRows = 0, this.errorMessage});

  final bool success;
  final int uploadedRows;
  final String? errorMessage;
}

/// 本機 Drift 資料一次性上傳到 Supabase(登入後呼叫)。尚無實作,見檔頭 TODO。
abstract interface class LocalToCloudUploader {
  /// 已上傳過(旗標已寫)就直接回成功、不做事;否則把 [local] 的使用者資料
  /// 以 [client] 目前登入者身分上傳。
  Future<CloudUploadResult> uploadIfNeeded(AppDatabase local, SupabaseClient client);
}
