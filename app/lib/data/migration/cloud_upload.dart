// 本機 Drift(舊 CoreData 匯入的落點)→ Supabase 的一次性上傳。
//
// 舊 iOS 版 CoreData 照舊在首啟時匯入本機 Drift(main.dart 的 CoreDataImporter);
// 雲端模式登入成功(或恢復 session)後,由 features/cloud_upload/
// cloud_upload_controller.dart 呼叫本檔的 [DriftToSupabaseUploader] 把本機資料
// 一次性搬上 Supabase。
//
// 對應規則(見 [DriftToSupabaseUploader] 文件):
// - 擁有者改寫:本機列的 userId(舊 Apple userIdentifier / 佔位使用者)一律改寫成
//   登入者 auth uid;子表(workout_exercises/workout_sets/template_exercises)也補
//   user_id = auth uid(RLS 要求)。
// - 系統動作:本機 isSystem 動作以「名稱 + categoryId」對應到雲端系統動作 id
//   (雲端 seed migration 的 md5 確定性 id,這裡直接查雲端拿,不在 client 重算),
//   不上傳;對不到的系統動作只在被引用時改為使用者自建動作上傳(保留本機 id)。
// - 系統模板:以名稱對應雲端系統模板 id(只用於 workouts.template_id 改寫),不上傳。
// - 使用者自建動作/模板照搬(保留本機 id,is_system = false)。
// - user_goals:雲端 unique(user_id),本機多筆取 updatedAt 最新一筆;雲端已有別筆
//   目標則略過本機(雲端優先,不覆寫)。
// - 草稿(endedAt 為 null):最多上傳一筆(startedAt 最新者)且只在雲端沒有別的
//   草稿時才上傳,其餘草稿連同子列略過——雲端 fetchDraft 只取最新一筆,多筆草稿會
//   讓舊的永遠卡在雲端。
//
// 冪等:一律以本機 id 當雲端 id,`INSERT ... ON CONFLICT (id) DO NOTHING`
// (PostgREST upsert ignoreDuplicates)——重跑不重複、也不覆寫雲端已有列;
// 先父後子,分批送出。全部成功才寫 [cloudUploadCompletedKey](依 auth uid 區分),
// 中途失敗不寫旗標,下次啟動或設定頁重試。
//
// 核對:`ON CONFLICT DO NOTHING` 遇到「id 已存在但屬於別的使用者」(RLS 下本人
// 看不到)會默默略過。所以每張表送完後,用本人身分回查剛送出的 id 有幾筆可見
// (不加 user_id 過濾:與雲端系統動作 id 相同的列靠 RLS 可見即算存在)。看不見的
// id 已被別的帳號佔用(例如裝置從別人的 iCloud 備份還原),那些資料本來就屬於
// 另一個帳號——計入各表略過筆數([CloudUploadResult.unownedCounts]),不算失敗,
// 上傳照常完成並寫旗標。回查本身失敗(網路等)才是失敗、不寫旗標。
//
// 子列連帶略過:被佔用的若是父列(整批 workouts 都屬於別的帳號),子列送出會撞
// FK/RLS(父 workout 不存在/不是本人;引用的動作須是系統或本人的,見 migration
// 20261111000600),重試也永遠失敗。所以每張表送完回查拿到「不可見 id 集合」後,
// 後面的子表送出前先剔除引用到不可見(或已被剔除)父 id 的列,同樣計入該子表的略過
// 筆數、不送、不算失敗。引用關係見 [CloudUploadTable.refs]。
//
// 自建動作例外(db-review 2026-11-11 MAJOR):動作是被共用的參照資料——裝置從別人的
// iCloud 備份還原後,本人繼續用對方建的自建動作 X 記訓練,X 的 id 在雲端屬於對方,
// 但引用 X 的訓練/模板/PR 是本人的。所以 exercises 回查不可見的動作先不剔除子列,
// 延到各子表送出前、剔除父列不可用的列「之後」,只對剩下真的要送的子列所引用的不可見
// 動作處理(每個動作一次上傳只處理一次):同名同分類的雲端系統動作 → 改指它;否則建
// 本人複本(確定性 id,見 [cloudUploadExerciseCopyId])。這樣整批屬於別人的歷史
// (workouts/templates 不可見,子列全被剔除)不會把對方的自建動作複製進本人帳號。
// exercise_id 只改送出的 payload,本機 Drift 不動。templates/workouts/
// workout_exercises 被佔用才維持剔除子列。
// personal_records.workout_id 沒有 FK,但當軟引用:指向的 workout 被別的帳號佔用
// (主上傳路徑回查不可見)時,這筆 PR 也是對方的資料,送出前先剔除、計入略過,不為它
// 建複本([CloudUploadTable.softRefs])。v1 補送路徑同樣套用:指向雲端不可見 workout
// 的 PR(被佔用,或使用者上傳後刪了)本來就從沒進過雲端,剔除、計入 skippedCounts。
// 已知殘留:workout_id 為 null、或指向本人可見 workout 的對方 PR,仍可能引用對方的
// 自建動作而觸發建複本(PR 本身送出後回查不可見照常計入略過,但複本留在本人帳號)。
//
// 複本送出後回查仍不可見(複本 id 也被別人佔用,實務上不該發生):不設計待人工處理的
// 失敗狀態——引用它的子列全部剔除、計入 [CloudUploadResult.unownedCounts],上傳照常
// 完成並寫旗標。沒能替換的不可見動作本身也計入 exercises 的略過筆數。
//
// 旗標版本:[cloudUploadCompletedKey] 是 v2。只有 v1 旗標([cloudUploadLegacyCompletedKey],
// 上述例外之前寫的)的使用者不整份重傳(會把上傳後在雲端刪掉的資料補回),只補 v1
// 因動作被佔用而漏送的子列,見 [DriftToSupabaseUploader] 的 `_repairLegacyUpload`。
// 寫 v2 時同時寫 v1(先 v1 後 v2):TestFlight 降版回只認 v1 的舊版時,不會因沒有
// v1 旗標而整份重傳。
// 補送的 workout_sets 不經 complete_workout,訓練的總量(total_volume 等)要對有補送
// 子列的 workout 呼叫 recompute_workout_summary 重算;雲端仍是草稿(WR001)或已刪
// (P0002)的略過該筆。主上傳路徑的 workouts 列本身就帶本機算好的總量,不必重算。
// 補送的前提:App 內刪自建動作是軟刪除(supabase_exercise_repository.dart 的 delete
// 只把 is_active 設 false,列仍可見),所以補送時「看不見的動作」≈ 被其他帳號佔用,
// 不是使用者自己刪的——補送不會把使用者刪掉的動作補回。以本機 id 上傳的系統動作
// (雲端對不到名稱的)同理:本機種子 id 每台裝置隨機產生(seed_data.dart 的
// generateUuidV4;CoreData 匯入對不到名稱的系統動作沿用原 id),看不見同樣是被佔用。
// 補送以子列(含 workout_sets)自己的 id 為準:子列已在雲端可見(v1 送過)就不重送、
// 不建複本。已知邊界:子列曾上傳成功、使用者在雲端刪掉、而其動作之後才變得不可見(需
// 雲端改系統動作名稱等罕見前提),補送會把它補回。
//
// 已知殘餘風險:重試從頭再送,兩次嘗試之間使用者在雲端刪掉的已上傳資料會被補回
// (沒有墓碑)。不做逐表檢查點——跳過已完成的父表後,雲端被刪的父列不會補回,
// 子表重送會撞 RLS/FK 永久失敗。
import 'dart:async' show TimeoutException;
import 'dart:convert' show utf8;
import 'dart:io' show HandshakeException, SocketException, TlsException;

import 'package:crypto/crypto.dart' show sha1;
import 'package:drift/drift.dart' show Expression, Insertable, Variable;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/app_database.dart';

/// 依 auth uid 區分的「已上傳完成」旗標 key(v2:自建動作被佔用改建複本之後)。
String cloudUploadCompletedKey(String uid) => 'cloud_upload_completed_v2_$uid';

/// v1 旗標 key。v1 完成時,引用「被別的帳號佔用的自建動作」的子列被當成不屬於本人
/// 而略過;只有這個旗標、沒有 v2 的使用者走補送,不整份重傳。
String cloudUploadLegacyCompletedKey(String uid) => 'cloud_upload_completed_$uid';

/// 自建動作複本 id 的 UUID v5 命名空間(固定值,改了會讓重試建出第二份複本)。
const _exerciseCopyNamespace = '6f1d3c2a-8b4e-4f7a-9d21-3e5b7c9a0f48';

/// 自建動作 id 被別的帳號佔用時,本人複本的 id:UUID v5(SHA-1),名稱 = 小寫 uid +
/// `:` + 舊 id 經 [_idKey] 正規化(與回查/改指比對同口徑)。同一使用者同一舊 id
/// 每次算出相同值,重試冪等(insert 撞到自己上次建的複本就忽略),不會多建。
String cloudUploadExerciseCopyId(String uid, String oldId) {
  final namespace = _exerciseCopyNamespace.replaceAll('-', '');
  final input = <int>[
    for (var i = 0; i < 32; i += 2) int.parse(namespace.substring(i, i + 2), radix: 16),
    ...utf8.encode('${uid.toLowerCase()}:${_idKey(oldId)}'),
  ];
  final bytes = List<int>.of(sha1.convert(input).bytes.take(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x50; // version 5
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// id 比對一律轉小寫:Postgres uuid 型別回傳小寫,本機日後若有大寫 id 來源,
/// 不轉的話本人資料會被全判成不可見。
/// 非字串(例如可為空的引用欄位是 null)回空字串,不會命中任何 id。
String _idKey(Object? id) => id is String ? id.toLowerCase() : '';

/// 失敗的粗分類,UI 依此挑使用者看得懂的文案(原始例外不外露)。
enum CloudUploadFailureKind {
  /// 網路中斷、逾時、連線錯誤。
  network,

  /// 其餘。
  other,
}

/// 把上傳過程的例外粗分成 [CloudUploadFailureKind]。
CloudUploadFailureKind classifyCloudUploadError(Object e) {
  if (e is SocketException ||
      e is TimeoutException ||
      e is HandshakeException ||
      e is TlsException) {
    return CloudUploadFailureKind.network;
  }
  if (e is PostgrestException) {
    // 非 JSON 的 HTTP 錯誤,PostgREST 把狀態碼當 code。
    final code = e.code ?? '';
    if (const {'408', '502', '503', '504'}.contains(code)) return CloudUploadFailureKind.network;
    return CloudUploadFailureKind.other;
  }
  // package:http 的 ClientException(連線被重置、DNS 失敗等)沒有直接依賴可引用,
  // 以型別名判斷。
  if (e.runtimeType.toString() == 'ClientException') return CloudUploadFailureKind.network;
  return CloudUploadFailureKind.other;
}

/// 一次性上傳的結果。
class CloudUploadResult {
  const CloudUploadResult({
    required this.success,
    this.skipped = false,
    this.uploadedRows = 0,
    this.tableCounts = const {},
    this.skippedCounts = const {},
    this.unownedCounts = const {},
    this.errorMessage,
    this.failureKind,
  });

  final bool success;

  /// true = 沒有實際上傳(已上傳過,或本機沒有可上傳資料)。
  final bool skipped;

  /// 送出的列數總和(含雲端已存在而被忽略的列——重跑時同樣計入)。
  final int uploadedRows;

  /// 各表送出的列數。
  final Map<String, int> tableCounts;

  /// 依規則刻意不上傳的列數(例如 `drafts`、`user_goals`)。
  final Map<String, int> skippedCounts;

  /// 各表「id 已被別的帳號佔用、本人看不見而未上傳」的筆數(只列大於 0 的表)。
  /// 這些資料本來就屬於另一個帳號,不算失敗;UI 只顯示總數,明細進 debugPrint。
  final Map<String, int> unownedCounts;

  /// [unownedCounts] 總和。
  int get unownedTotal => unownedCounts.values.fold(0, (a, b) => a + b);

  /// 原始錯誤訊息(給 log 用,不直接顯示給使用者)。
  final String? errorMessage;

  /// 失敗時的分類(成功為 null)。
  final CloudUploadFailureKind? failureKind;
}

/// 上傳時要 ensure 的 users 列資料(id 一律是 auth uid)。
class CloudUserProfile {
  const CloudUserProfile({this.name, this.email});

  final String? name;
  final String? email;
}

/// Supabase 端的 seam:上傳流程只透過這個介面碰雲端,測試換成記憶體假件。
abstract interface class CloudUploadSink {
  /// 目前登入者 auth uid;未登入為 null。
  String? get currentUid;

  /// 雲端系統動作(欄位至少 id、name、category_id)。
  Future<List<Map<String, dynamic>>> fetchSystemExercises();

  /// 雲端系統模板(欄位至少 id、name)。
  Future<List<Map<String, dynamic>>> fetchSystemTemplates();

  /// 登入者在雲端的 user_goals id(unique(user_id),最多一筆)。
  Future<String?> fetchUserGoalId(String uid);

  /// 登入者在雲端的草稿訓練(ended_at is null)id。
  Future<List<String>> fetchDraftWorkoutIds(String uid);

  /// users 列不存在才建(已存在不動)。
  Future<void> ensureUser(String uid, CloudUserProfile profile);

  /// 以 id 為衝突鍵批次插入,已存在的列忽略(ON CONFLICT (id) DO NOTHING)。
  Future<void> insertIgnoringDuplicates(String table, List<Map<String, dynamic>> rows);

  /// 用本人身分回查 [table] 裡 [ids] 哪些「可見」,回傳可見的 id 集合。刻意不加
  /// user_id 過濾:RLS 下別人的同 id 列看不到(不在集合內),但與系統動作/模板 id
  /// 相同的列看得到(算存在)。要拿集合而不只是數量,是因為子表要靠它剔除引用到
  /// 不可見父列的列。呼叫端負責分批,單次 [ids] 不宜過長。
  Future<Set<String>> fetchVisibleIds(String table, List<String> ids);

  /// 以雲端 workout_sets 重算已完成訓練的總量(RPC `recompute_workout_summary`)。
  /// 雲端仍是草稿拋 [PostgrestException] code `WR001`,找不到(已刪/不是本人)拋
  /// `P0002`,由呼叫端決定是否略過。
  Future<void> recomputeWorkoutSummary(String workoutId);
}

class SupabaseCloudUploadSink implements CloudUploadSink {
  SupabaseCloudUploadSink(this._client);

  final SupabaseClient _client;

  @override
  String? get currentUid => _client.auth.currentUser?.id;

  @override
  Future<List<Map<String, dynamic>>> fetchSystemExercises() =>
      _client.from('exercises').select('id, name, category_id').eq('is_system', true).order('id');

  @override
  Future<List<Map<String, dynamic>>> fetchSystemTemplates() =>
      _client.from('templates').select('id, name').eq('is_system', true).order('id');

  @override
  Future<String?> fetchUserGoalId(String uid) async {
    final row =
        await _client.from('user_goals').select('id').eq('user_id', uid).maybeSingle();
    return row?['id'] as String?;
  }

  @override
  Future<List<String>> fetchDraftWorkoutIds(String uid) async {
    final rows = await _client
        .from('workouts')
        .select('id')
        .eq('user_id', uid)
        .isFilter('ended_at', null);
    return [for (final r in rows) r['id'] as String];
  }

  @override
  Future<void> ensureUser(String uid, CloudUserProfile profile) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('users').upsert(
      {'id': uid, 'name': profile.name, 'email': profile.email, 'created_at': now, 'updated_at': now},
      onConflict: 'id',
      ignoreDuplicates: true,
    );
  }

  @override
  Future<void> insertIgnoringDuplicates(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _client.from(table).upsert(rows, onConflict: 'id', ignoreDuplicates: true);
  }

  @override
  Future<Set<String>> fetchVisibleIds(String table, List<String> ids) async {
    if (ids.isEmpty) return const {};
    final rows = await _client.from(table).select('id').inFilter('id', ids);
    return {for (final r in rows) r['id'] as String};
  }

  @override
  Future<void> recomputeWorkoutSummary(String workoutId) =>
      _client.rpc<void>('recompute_workout_summary', params: {'p_workout_id': workoutId});
}

/// 本機 Drift 資料一次性上傳到 Supabase(登入後呼叫)。
abstract interface class LocalToCloudUploader {
  /// [uid] 是否已上傳完成(旗標已寫)。
  bool isCompleted(String uid);

  /// [uid] 是否只有 v1 完成旗標(未完成 v2)。這類使用者的 [uploadIfNeeded] 只做補送,
  /// 呼叫端據此走靜默路徑(不顯示「正在同步」)。
  bool isLegacyCompleted(String uid);

  /// 本機 Drift 是否有可上傳的使用者資料(系統動作/系統模板種子不算)。
  Future<bool> hasUploadableData(AppDatabase local);

  /// 已上傳過(旗標已寫)就直接回成功、不做事;否則把 [local] 的使用者資料以
  /// [sink] 目前登入者身分上傳。[ensureUser] 非 null 時先 ensure users 列。
  /// 例外一律收成 `success: false`,不往外拋。
  Future<CloudUploadResult> uploadIfNeeded(
    AppDatabase local,
    CloudUploadSink sink, {
    CloudUserProfile? ensureUser,
  });
}

/// Drift 產生的 SQL 欄名 → Postgres 欄名的例外(同 supabase_mapping.dart 的
/// kDriftToPgColumn;刻意不 import 該檔,上傳流程不依賴 repository 層)。
const _driftToPgColumn = <String, String>{
  'video_u_r_l': 'video_url',
  'image_u_r_l': 'image_url',
};

Map<String, dynamic> _rowJson(Insertable<dynamic> row) {
  final out = <String, dynamic>{};
  row.toColumns(false).forEach((String column, Expression<Object> expression) {
    final value = (expression as Variable<Object>).value;
    out[_driftToPgColumn[column] ?? column] =
        value is DateTime ? value.toUtc().toIso8601String() : value;
  });
  return out;
}

class DriftToSupabaseUploader implements LocalToCloudUploader {
  DriftToSupabaseUploader({
    required SharedPreferences prefs,
    this.batchSize = 500,
    this.verifyBatchSize = 100,
  })  : _prefs = prefs,
        assert(batchSize > 0),
        assert(verifyBatchSize > 0);

  final SharedPreferences _prefs;

  /// 每次 PostgREST 請求最多送幾列。
  final int batchSize;

  /// 核對時每次 `id in (...)` 查詢最多帶幾個 id。id 是 36 字元 UUID,加分隔符約
  /// 37 字元;100 個 ≈ 3.7KB 的 query string,低於常見閘道/代理 8KB 的 URL 與
  /// header 上限並留有編碼膨脹餘裕(500 個會逼近 20KB 而被 414/431 擋掉)。
  final int verifyBatchSize;

  @override
  bool isCompleted(String uid) => _prefs.getBool(cloudUploadCompletedKey(uid)) ?? false;

  @override
  bool isLegacyCompleted(String uid) =>
      !isCompleted(uid) && (_prefs.getBool(cloudUploadLegacyCompletedKey(uid)) ?? false);

  @override
  Future<bool> hasUploadableData(AppDatabase local) async {
    Future<bool> any(Future<Object?> query) async => await query != null;
    return await any((local.select(local.workouts)..limit(1)).getSingleOrNull()) ||
        await any((local.select(local.bodyWeights)..limit(1)).getSingleOrNull()) ||
        await any((local.select(local.personalRecords)..limit(1)).getSingleOrNull()) ||
        await any((local.select(local.userGoals)..limit(1)).getSingleOrNull()) ||
        await any((local.select(local.powerLiftRecords)..limit(1)).getSingleOrNull()) ||
        await any((local.select(local.exercises)
              ..where((e) => e.isSystem.equals(false))
              ..limit(1))
            .getSingleOrNull()) ||
        await any((local.select(local.templates)
              ..where((t) => t.isSystem.equals(false))
              ..limit(1))
            .getSingleOrNull());
  }

  @override
  Future<CloudUploadResult> uploadIfNeeded(
    AppDatabase local,
    CloudUploadSink sink, {
    CloudUserProfile? ensureUser,
  }) async {
    try {
      final uid = sink.currentUid;
      if (uid == null) {
        return const CloudUploadResult(
          success: false,
          errorMessage: '尚未登入,無法上傳',
          failureKind: CloudUploadFailureKind.other,
        );
      }
      if (isCompleted(uid)) {
        return const CloudUploadResult(success: true, skipped: true);
      }
      // v1 已完成:不整份重傳(使用者上傳後在雲端刪掉的資料會被補回),只補 v1 因
      // 自建動作被佔用而漏送的子列。v1 完成後本來就不再 ensure users,這裡照舊。
      if (isLegacyCompleted(uid)) {
        return await _repairLegacyUpload(local, sink, uid);
      }
      if (ensureUser != null) {
        await sink.ensureUser(uid, ensureUser);
      }
      if (!await hasUploadableData(local)) {
        return const CloudUploadResult(success: true, skipped: true);
      }

      final plan = await buildCloudUploadPlan(local, sink, uid);
      final run = _UploadRun(uid, plan.systemExerciseIds);
      for (final entry in plan.tables) {
        final sent = await _sendTable(sink, entry, run);
        if (entry.table == 'exercises') {
          // 不可見的動作先不算不可用:子表送出前才決定改指/建複本(見檔頭)。
          run.pendingExercises.addAll({
            for (final row in sent.rows)
              if (sent.invisible.contains(row['id'])) _idKey(row['id']): row,
          });
          run.counts[entry.table] = sent.rows.length - sent.invisible.length;
          continue;
        }
        // 「共 N 筆」只算本人確實可用的:送出後才發現不可見的列已計入略過,不重複算。
        // exercises 已先寫入計數,建複本時才累加,這裡不能覆蓋。
        run.counts[entry.table] = sent.rows.length - sent.invisible.length;
        run.unusable[entry.table] = {...sent.droppedIds, for (final id in sent.invisible) _idKey(id)};
        final unowned = sent.droppedIds.length + sent.invisible.length;
        if (unowned > 0) run.unownedCounts[entry.table] = unowned;
      }
      // 不可見且最後沒被替換的動作(沒有要送的子列引用、或複本仍不可見)計入略過。
      final unreplaced =
          run.pendingExercises.keys.where((key) => !run.exerciseRemap.containsKey(key)).length;
      if (unreplaced > 0) run.unownedCounts['exercises'] = unreplaced;

      await _markCompleted(uid);
      return CloudUploadResult(
        success: true,
        uploadedRows: run.counts.values.fold(0, (a, b) => a + b),
        tableCounts: run.counts,
        skippedCounts: plan.skippedCounts,
        unownedCounts: run.unownedCounts,
      );
    } catch (e) {
      return CloudUploadResult(
        success: false,
        errorMessage: '$e',
        failureKind: classifyCloudUploadError(e),
      );
    }
  }

  /// v1 旗標使用者的補送:先檢查上傳計畫裡被子列引用、以本機 id 上傳的動作(自建,
  /// 以及雲端對不到名稱的系統動作)在雲端是否可見(候選子列一律取自
  /// [buildCloudUploadPlan],已排除不上傳的草稿與系統模板子列)。全部可見 → 不送任何
  /// 資料、直接寫 v2。有不可見的 → 引用它們的 workout_exercises、template_exercises、
  /// personal_records,以及這些 workout_exercises 底下的 workout_sets,再回查子列自己的
  /// id:已在雲端可見的(v1 已送出)不重送,只補不可見的,送出前才為剩下要送的子列建
  /// 複本(或改指系統動作)。父列(workouts/templates)或 PR 軟引用的 workout 在雲端
  /// 看不見表示使用者上傳後刪了(或被佔用),該子列跳過、不補回父列,也不為它建複本。
  Future<CloudUploadResult> _repairLegacyUpload(
    AppDatabase local,
    CloudUploadSink sink,
    String uid,
  ) async {
    final plan = await buildCloudUploadPlan(local, sink, uid);
    final referenced = _referencedExerciseKeys(plan.tables);
    // 不分自建或系統:計畫裡的動作列都以本機 id 上傳,系統動作的本機種子 id 每台裝置
    // 不同(見檔頭),看不見同樣代表 v1 時引用它的子列被略過。
    final candidates = [
      for (final row in plan.rowsOf('exercises'))
        if (referenced.contains(_idKey(row['id']))) row,
    ];
    final invisible = await _findInvisible(sink, 'exercises', candidates);
    final run = _UploadRun(uid, plan.systemExerciseIds);
    final skipped = <String, int>{};
    if (invisible.isNotEmpty) {
      run.pendingExercises.addAll({
        for (final row in candidates)
          if (invisible.contains(row['id'])) _idKey(row['id']): row,
      });

      final gone = {for (final id in invisible) _idKey(id)};
      bool usesGone(Map<String, dynamic> row) => gone.contains(_idKey(row['exercise_id']));
      // 引用不可見動作、且自己的 id 在雲端看不見的子列才補:可見的 v1 已送出,不重送也不
      // 為它建複本(動作可能是之後才變得不可見的)。
      Future<List<Map<String, dynamic>>> missing(String table, List<Map<String, dynamic>> rows) async {
        final notInCloud = await _findInvisible(sink, table, rows);
        return [for (final r in rows) if (notInCloud.contains(r['id'])) r];
      }

      final usingWorkoutExercises = plan.rowsOf('workout_exercises').where(usesGone).toList();
      final workoutOf = {
        for (final we in usingWorkoutExercises) _idKey(we['id']): we['workout_id'] as String,
      };
      final workoutExercises = await missing('workout_exercises', usingWorkoutExercises);
      final templateExercises =
          await missing('template_exercises', plan.rowsOf('template_exercises').where(usesGone).toList());
      final personalRecords =
          await missing('personal_records', plan.rowsOf('personal_records').where(usesGone).toList());
      // workout_sets 同樣以自己的 id 為準,範圍是所有引用不可見動作的 workout_exercises
      // (含已可見而不重送的):補送在 workout_sets 中途失敗時,重試的 workout_exercises
      // 已可見,只看重送的 workout_exercises 會讓它的 set 永遠補不回。set 不引用動作,
      // 不會因此建複本。
      final workoutSets = await missing('workout_sets', [
        for (final s in plan.rowsOf('workout_sets'))
          if (workoutOf.containsKey(_idKey(s['workout_exercise_id']))) s,
      ]);
      final subset = <String, List<Map<String, dynamic>>>{
        'template_exercises': templateExercises,
        'workout_exercises': workoutExercises,
        'workout_sets': workoutSets,
        'personal_records': personalRecords,
      };
      // 父列看不見 = 使用者上傳後刪了:同時記進 deleted,子列剔除算刻意略過而非 unowned。
      // 補送路徑無法區分父列是使用者刪的、還是被別的帳號佔用(v1 時回查不可見就略過,
      // 兩者在雲端都只是「本人看不見」),一律記 skippedCounts。unusable 與 deleted 各自
      // 一份 Set:_sendTable 會往 deleted 加孫表的 id,不能連帶改到 unusable。
      // PR 的 workout_id 是軟引用(可為 null),一併回查,指向不可見 workout 的 PR 剔除。
      final goneWorkouts = {
        for (final id in await _findInvisibleIds(sink, 'workouts', [
          for (final we in workoutExercises) we['workout_id'] as String,
          for (final pr in personalRecords)
            if (pr['workout_id'] is String) pr['workout_id'] as String,
        ]))
          _idKey(id),
      };
      run.unusable['workouts'] = {...goneWorkouts};
      run.deleted['workouts'] = {...goneWorkouts};
      final goneTemplates = {
        for (final id in await _findInvisibleIds(sink, 'templates', [
          for (final te in templateExercises) te['template_id'] as String,
        ]))
          _idKey(id),
      };
      run.unusable['templates'] = {...goneTemplates};
      run.deleted['templates'] = {...goneTemplates};
      // 有補送子列(workout_exercises 或 workout_sets,送出且本人可見)的 workout,原樣 id。
      final repairedWorkouts = <String, String>{};

      for (final entry in plan.tables) {
        final rows = subset[entry.table];
        if (rows == null) continue;
        final sent = await _sendTable(
            sink, CloudUploadTable(entry.table, rows, refs: entry.refs, softRefs: entry.softRefs), run);
        run.counts[entry.table] = sent.rows.length - sent.invisible.length;
        run.unusable[entry.table] = {...sent.droppedIds, for (final id in sent.invisible) _idKey(id)};
        // 父列已被使用者刪掉而跳過的,是刻意不補,記在 skippedCounts;子列自己的 id
        // 被別的帳號佔用、或引用的動作複本仍不可見而剔除的,才算 unowned。
        final deleted = sent.droppedIds.intersection(run.deleted[entry.table] ?? const {});
        if (deleted.isNotEmpty) skipped[entry.table] = deleted.length;
        final unowned = sent.droppedIds.length - deleted.length + sent.invisible.length;
        if (unowned > 0) run.unownedCounts[entry.table] = unowned;
        if (entry.table == 'workout_exercises') {
          for (final we in sent.rows) {
            if (!sent.invisible.contains(we['id'])) {
              final workoutId = we['workout_id'] as String;
              repairedWorkouts.putIfAbsent(_idKey(workoutId), () => workoutId);
            }
          }
        }
        if (entry.table == 'workout_sets') {
          for (final ws in sent.rows) {
            final workoutId = workoutOf[_idKey(ws['workout_exercise_id'])];
            if (workoutId != null && !sent.invisible.contains(ws['id'])) {
              repairedWorkouts.putIfAbsent(_idKey(workoutId), () => workoutId);
            }
          }
          // 子列都送完才重算(見檔頭)。不看本機 ended_at:本機草稿可能已在別台裝置完成,
          // 雲端狀態才準;雲端仍是草稿或已刪的由 _recomputeSummary 略過。
          for (final workoutId in repairedWorkouts.values) {
            await _recomputeSummary(sink, workoutId);
          }
        }
      }
    }

    await _markCompleted(uid);
    // 「送出筆數」只算子表實際送出(且本人可見)的列,不含動作複本:只建了複本、子列
    // 卻沒落地時,靜默補送不該顯示「已同步」。
    final uploadedRows = run.counts.entries
        .where((e) => e.key != 'exercises')
        .fold(0, (a, e) => a + e.value);
    return CloudUploadResult(
      success: true,
      skipped: uploadedRows == 0,
      uploadedRows: uploadedRows,
      tableCounts: run.counts,
      skippedCounts: skipped,
      unownedCounts: run.unownedCounts,
    );
  }

  /// 補送後重算 [workoutId] 的總量。雲端仍是草稿(WR001,完成時 complete_workout 會算)
  /// 或已刪(P0002)→ 略過該筆,不讓單筆中斷整個補送;其他錯誤照舊拋出(補送失敗、
  /// 不寫 v2,下次重試)。
  Future<void> _recomputeSummary(CloudUploadSink sink, String workoutId) async {
    try {
      await sink.recomputeWorkoutSummary(workoutId);
    } on PostgrestException catch (e) {
      if (e.code != 'WR001' && e.code != 'P0002') rethrow;
      debugPrint('cloud upload repair: skip recompute $workoutId (${e.code})');
    }
  }

  /// 寫完成旗標:v2,同時寫 v1(TestFlight 降版回只認 v1 的舊版時不整份重傳)。
  /// 先 v1 後 v2:兩次寫入之間中斷時只留 v1,新版下次走補送(只補缺)、降版也認得;
  /// 反過來只留 v2 的話,降版回舊版會因沒有 v1 而整份重傳。
  Future<void> _markCompleted(String uid) async {
    await _prefs.setBool(cloudUploadLegacyCompletedKey(uid), true);
    await _prefs.setBool(cloudUploadCompletedKey(uid), true);
  }

  /// 送出一張表:先剔除引用到不可用父列(含 [CloudUploadTable.softRefs])的列;
  /// 剩下的列引用到的待替換動作([_UploadRun.pendingExercises])此時才改指系統動作
  /// 或建本人複本;exercise_id 類欄位改指 [_UploadRun.exerciseRemap] 後,再剔除引用到
  /// 替換失敗動作的列,分批送出後回查。回傳實際送出的列、剔除列的 id(小寫)、回查不可見的 id(保留本機原樣大小寫)。
  /// 剔除的列若是因 [_UploadRun.deleted] 的父列,id 也記進 deleted(讓孫表沿用同一理由)。
  Future<({List<Map<String, dynamic>> rows, Set<String> droppedIds, Set<String> invisible})> _sendTable(
    CloudUploadSink sink,
    CloudUploadTable entry,
    _UploadRun run,
  ) async {
    final exerciseColumns = [
      for (final ref in entry.refs)
        if (ref.parentTable == 'exercises') ref.column,
    ];
    final droppedIds = <String>{};
    final dropRefs = [...entry.refs, ...entry.softRefs];
    bool keep(Map<String, dynamic> row) {
      bool goneIn(Map<String, Set<String>> sets) =>
          dropRefs.any((ref) => sets[ref.parentTable]?.contains(_idKey(row[ref.column])) ?? false);
      if (!goneIn(run.unusable)) return true;
      droppedIds.add(_idKey(row['id']));
      if (goneIn(run.deleted)) run.deleted.putIfAbsent(entry.table, () => {}).add(_idKey(row['id']));
      return false;
    }

    final kept = entry.rows.where(keep).toList();
    // 父列剔除之後才處理動作:只為真的會送出的子列建複本(見檔頭)。
    final toReplace = <String, Map<String, dynamic>>{
      for (final row in kept)
        for (final column in exerciseColumns)
          if (run.pendingExercises.containsKey(_idKey(row[column])) &&
              !run.exerciseRemap.containsKey(_idKey(row[column])) &&
              !(run.unusable['exercises']?.contains(_idKey(row[column])) ?? false))
            _idKey(row[column]): run.pendingExercises[_idKey(row[column])]!,
    };
    if (toReplace.isNotEmpty) await _replaceInvisibleExercises(sink, toReplace.values.toList(), run);
    final rows = <Map<String, dynamic>>[];
    for (final original in kept) {
      var row = original;
      for (final column in exerciseColumns) {
        final to = run.exerciseRemap[_idKey(row[column])];
        if (to != null) row = {...row, column: to};
      }
      // 複本仍不可見的動作已記進 unusable,引用它的列這裡剔除(不送、不撞 FK)。
      if (keep(row)) rows.add(row);
    }
    await _insertBatched(sink, entry.table, rows);
    final invisible = await _findInvisible(sink, entry.table, rows);
    return (rows: rows, droppedIds: droppedIds, invisible: invisible);
  }

  /// [rows] 是送出後不可見(id 被別的帳號佔用)且有要送的子列引用的自建動作:同名同
  /// 分類的雲端系統動作存在就改指它,否則建本人複本(確定性 id)。對應記進
  /// [_UploadRun.exerciseRemap],可見的複本數累加到 exercises 的計數。複本送出後回查
  /// 仍不可見的:不改指(子列改指一個看不見的動作只會撞 FK),舊 id 記進
  /// [_UploadRun.unusable] 讓引用它的子列被剔除、計入略過,上傳照常完成(見檔頭)。
  Future<void> _replaceInvisibleExercises(
    CloudUploadSink sink,
    List<Map<String, dynamic>> rows,
    _UploadRun run,
  ) async {
    final copies = <Map<String, dynamic>>[];
    final copyOf = <String, String>{};
    for (final row in rows) {
      final oldKey = _idKey(row['id']);
      final systemId =
          run.systemExerciseIds[_exerciseKey(row['name'] as String, row['category_id'] as String)];
      if (systemId != null) {
        run.exerciseRemap[oldKey] = systemId;
        continue;
      }
      final copyId = cloudUploadExerciseCopyId(run.uid, oldKey);
      copies.add({...row, 'id': copyId, 'is_system': false, 'user_id': run.uid});
      copyOf[copyId] = oldKey;
    }
    await _insertBatched(sink, 'exercises', copies);
    final invisible = await _findInvisible(sink, 'exercises', copies);
    copyOf.forEach((copyId, oldKey) {
      if (invisible.contains(copyId)) {
        run.unusable.putIfAbsent('exercises', () => {}).add(oldKey);
      } else {
        run.exerciseRemap[oldKey] = copyId;
      }
    });
    final visibleCopies = copies.length - invisible.length;
    run.counts.update('exercises', (n) => n + visibleCopies, ifAbsent: () => visibleCopies);
  }

  Future<void> _insertBatched(CloudUploadSink sink, String table, List<Map<String, dynamic>> rows) async {
    for (var i = 0; i < rows.length; i += batchSize) {
      final end = i + batchSize < rows.length ? i + batchSize : rows.length;
      await sink.insertIgnoringDuplicates(table, rows.sublist(i, end));
    }
  }

  /// 回查 [sent] 剛送出的 id 在雲端(本人身分)哪些看不見(id 已被別的帳號佔用),
  /// 回傳看不見的 id 集合(保留本機原樣的大小寫)。查詢失敗直接拋出,由呼叫端當成上傳失敗。
  Future<Set<String>> _findInvisible(
    CloudUploadSink sink,
    String table,
    List<Map<String, dynamic>> sent,
  ) =>
      _findInvisibleIds(sink, table, [for (final r in sent) r['id'] as String]);

  /// [ids] 在雲端(本人身分)看不見的那些,依 [verifyBatchSize] 分批查。
  Future<Set<String>> _findInvisibleIds(CloudUploadSink sink, String table, List<String> idList) async {
    final ids = idList.toSet().toList();
    final visible = <String>{};
    for (var i = 0; i < ids.length; i += verifyBatchSize) {
      final end = i + verifyBatchSize < ids.length ? i + verifyBatchSize : ids.length;
      visible.addAll([for (final id in await sink.fetchVisibleIds(table, ids.sublist(i, end))) _idKey(id)]);
    }
    return {for (final id in ids) if (!visible.contains(_idKey(id))) id};
  }
}

/// 一次上傳(或 v1 補送)過程的累積狀態。
class _UploadRun {
  _UploadRun(this.uid, this.systemExerciseIds);

  /// 登入者 auth uid(複本的擁有者與 id 推導)。
  final String uid;

  /// 見 [CloudUploadPlan.systemExerciseIds]。
  final Map<String, String> systemExerciseIds;

  /// 各表本人確實可用的列數。
  final counts = <String, int>{};
  final unownedCounts = <String, int>{};

  /// 表名 → 該表「雲端上沒有本人可用的列」的 id(一律小寫,與回查比對同口徑):
  /// 回查看不見的,加上因父列不可用而被剔除沒送的,以及複本仍不可見的舊動作 id。
  /// 子表依 [CloudUploadTable.refs] 查這裡決定要不要剔除。待替換或已改指的動作不放進來。
  final unusable = <String, Set<String>>{};

  /// [unusable] 中「父列被使用者在雲端刪掉」這個理由的子集(只有 v1 補送會用到):
  /// 因此剔除的子列算刻意略過(skippedCounts),不是 unowned。
  final deleted = <String, Set<String>>{};

  /// 小寫舊動作 id → 不可見的自建動作列:等子表送出前確認有要送的子列引用,才改指或建複本。
  final pendingExercises = <String, Map<String, dynamic>>{};

  /// 小寫舊動作 id → 改指的動作 id(本人複本或雲端系統動作)。每個舊 id 只處理一次。
  final exerciseRemap = <String, String>{};
}

/// [tables] 裡所有引用 exercises 的欄位值(小寫)。
Set<String> _referencedExerciseKeys(Iterable<CloudUploadTable> tables) => {
      for (final t in tables)
        for (final ref in t.refs)
          if (ref.parentTable == 'exercises')
            for (final row in t.rows) _idKey(row[ref.column]),
    };

/// 子表的一條外鍵引用:[column] 的值是 [parentTable] 的 id。
class CloudUploadRef {
  const CloudUploadRef(this.column, this.parentTable);

  final String column;
  final String parentTable;
}

/// 一張表要送出的列(已套用對應規則)。
class CloudUploadTable {
  const CloudUploadTable(this.table, this.rows, {this.refs = const [], this.softRefs = const []});

  final String table;
  final List<Map<String, dynamic>> rows;

  /// 這張表的 FK/RLS 引用(只列要求父列「本人可用」的,見 schema 與 RLS)。
  /// workouts.template_id、personal_records.workout_id 沒有 FK,不列。
  final List<CloudUploadRef> refs;

  /// 沒有 FK 的軟引用:父列在主上傳路徑回查不可見(被別的帳號佔用)時,這列也是對方的
  /// 資料,送出前剔除、計入略過。v1 補送路徑同樣套用(見 `_repairLegacyUpload`)。
  final List<CloudUploadRef> softRefs;
}

/// 上傳計畫:[tables] 依父子順序排列。
class CloudUploadPlan {
  const CloudUploadPlan(
    this.tables,
    this.skippedCounts, {
    this.systemExerciseIds = const {},
  });

  final List<CloudUploadTable> tables;
  final Map<String, int> skippedCounts;

  /// 雲端系統動作:`_exerciseKey(名稱, categoryId)` → id。自建動作被佔用時先拿它找
  /// 同名同分類的系統動作改指,不必建複本。
  final Map<String, String> systemExerciseIds;

  List<Map<String, dynamic>> rowsOf(String table) =>
      tables.firstWhere((t) => t.table == table, orElse: () => const CloudUploadTable('', [])).rows;
}

String _exerciseKey(String name, String categoryId) => '$name\u0000$categoryId';

/// 把本機 Drift 全部使用者資料轉成雲端列(純讀,不寫任何東西)。
Future<CloudUploadPlan> buildCloudUploadPlan(
  AppDatabase local,
  CloudUploadSink sink,
  String uid,
) async {
  final skipped = <String, int>{};
  void skip(String key, [int n = 1]) {
    if (n > 0) skipped[key] = (skipped[key] ?? 0) + n;
  }

  // ---------- 讀本機 ----------
  final exercises = await local.select(local.exercises).get();
  final templates = await local.select(local.templates).get();
  final templateExercises = await local.select(local.templateExercises).get();
  final workouts = await local.select(local.workouts).get();
  final workoutExercises = await local.select(local.workoutExercises).get();
  final workoutSets = await local.select(local.workoutSets).get();
  final bodyWeights = await local.select(local.bodyWeights).get();
  final personalRecords = await local.select(local.personalRecords).get();
  final userGoals = await local.select(local.userGoals).get();
  final powerLifts = await local.select(local.powerLiftRecords).get();

  // ---------- 系統動作 / 系統模板對應 ----------
  final cloudSystemExercises = {
    for (final r in await sink.fetchSystemExercises())
      _exerciseKey(r['name'] as String, r['category_id'] as String): r['id'] as String,
  };
  final cloudSystemTemplates = {
    for (final r in await sink.fetchSystemTemplates()) r['name'] as String: r['id'] as String,
  };

  // 模板:系統模板(對到雲端)只記對應;Drift 種子的系統模板(userId 為 null)對不到
  // 雲端就丟棄;CoreData 帶來、標了 isSystem 但有擁有者的模板對不到時當使用者模板上傳。
  final templateIdMap = <String, String>{};
  final uploadTemplates = <Template>[];
  for (final t in templates) {
    if (t.isSystem) {
      final cloudId = cloudSystemTemplates[t.name];
      if (cloudId != null) {
        templateIdMap[t.id] = cloudId;
        continue;
      }
      if (t.userId == null) {
        skip('system_templates');
        continue;
      }
    }
    uploadTemplates.add(t);
  }
  final uploadTemplateIds = {for (final t in uploadTemplates) t.id};
  final uploadTemplateExercises =
      templateExercises.where((te) => uploadTemplateIds.contains(te.templateId)).toList();
  skip('system_template_exercises', templateExercises.length - uploadTemplateExercises.length);

  // 訓練草稿:最多一筆(startedAt 最新),且雲端沒有別的草稿。
  final drafts = workouts.where((w) => w.endedAt == null).toList()
    ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  final droppedWorkoutIds = <String>{};
  if (drafts.isNotEmpty) {
    final cloudDrafts = await sink.fetchDraftWorkoutIds(uid);
    final keep = drafts.first;
    final cloudHasOtherDraft = cloudDrafts.any((id) => _idKey(id) != _idKey(keep.id));
    for (final d in drafts) {
      if (d.id != keep.id || cloudHasOtherDraft) droppedWorkoutIds.add(d.id);
    }
    skip('drafts', droppedWorkoutIds.length);
  }
  final uploadWorkouts = workouts.where((w) => !droppedWorkoutIds.contains(w.id)).toList();
  final uploadWorkoutIds = {for (final w in uploadWorkouts) w.id};
  final uploadWorkoutExercises =
      workoutExercises.where((we) => uploadWorkoutIds.contains(we.workoutId)).toList();
  final uploadWeIds = {for (final we in uploadWorkoutExercises) we.id};
  final uploadWorkoutSets =
      workoutSets.where((s) => uploadWeIds.contains(s.workoutExerciseId)).toList();

  // 動作:系統動作對到雲端 → 只記對應;其餘(自建、佔位、對不到的系統動作)保留本機
  // id 當使用者動作上傳——但對不到的系統動作只在被引用時才上傳,避免本機種子與雲端
  // 種子不一致時把整套種子灌成使用者動作。
  final referencedExerciseIds = {
    for (final we in uploadWorkoutExercises) we.exerciseId,
    for (final te in uploadTemplateExercises) te.exerciseId,
    for (final pr in personalRecords) pr.exerciseId,
  };
  final exerciseIdMap = <String, String>{};
  final uploadExercises = <Exercise>[];
  for (final e in exercises) {
    if (e.isSystem) {
      final cloudId = cloudSystemExercises[_exerciseKey(e.name, e.categoryId)];
      if (cloudId != null) {
        exerciseIdMap[e.id] = cloudId;
        continue;
      }
      if (!referencedExerciseIds.contains(e.id)) {
        skip('system_exercises');
        continue;
      }
    }
    exerciseIdMap[e.id] = e.id;
    uploadExercises.add(e);
  }
  String mapExercise(String id) => exerciseIdMap[id] ?? id;

  // user_goals:雲端 unique(user_id),取 updatedAt 最新一筆。
  final sortedGoals = [...userGoals]..sort((a, b) {
      final byUpdated = b.updatedAt.compareTo(a.updatedAt);
      return byUpdated != 0 ? byUpdated : b.createdAt.compareTo(a.createdAt);
    });
  final uploadGoals = <UserGoal>[];
  if (sortedGoals.isNotEmpty) {
    final latest = sortedGoals.first;
    final cloudGoalId = await sink.fetchUserGoalId(uid);
    if (cloudGoalId == null || _idKey(cloudGoalId) == _idKey(latest.id)) {
      uploadGoals.add(latest);
      skip('user_goals', sortedGoals.length - 1);
    } else {
      skip('user_goals', sortedGoals.length);
    }
  }

  Map<String, dynamic> owned(Insertable<dynamic> row) => _rowJson(row)..['user_id'] = uid;

  final tables = <CloudUploadTable>[
    CloudUploadTable('exercises', [
      for (final e in uploadExercises) owned(e)..['is_system'] = false,
    ]),
    CloudUploadTable('templates', [
      for (final t in uploadTemplates) owned(t)..['is_system'] = false,
    ]),
    CloudUploadTable('template_exercises', [
      for (final te in uploadTemplateExercises) owned(te)..['exercise_id'] = mapExercise(te.exerciseId),
    ], refs: const [
      CloudUploadRef('template_id', 'templates'),
      CloudUploadRef('exercise_id', 'exercises'),
    ]),
    CloudUploadTable('workouts', [
      for (final w in uploadWorkouts)
        owned(w)..['template_id'] = w.templateId == null ? null : (templateIdMap[w.templateId] ?? w.templateId),
    ]),
    CloudUploadTable('workout_exercises', [
      for (final we in uploadWorkoutExercises) owned(we)..['exercise_id'] = mapExercise(we.exerciseId),
    ], refs: const [
      CloudUploadRef('workout_id', 'workouts'),
      CloudUploadRef('exercise_id', 'exercises'),
    ]),
    CloudUploadTable('workout_sets', [
      for (final s in uploadWorkoutSets) owned(s),
    ], refs: const [CloudUploadRef('workout_exercise_id', 'workout_exercises')]),
    CloudUploadTable('body_weights', [for (final b in bodyWeights) owned(b)]),
    CloudUploadTable('personal_records', [
      for (final pr in personalRecords) owned(pr)..['exercise_id'] = mapExercise(pr.exerciseId),
    ], refs: const [
      CloudUploadRef('exercise_id', 'exercises'),
    ], softRefs: const [
      CloudUploadRef('workout_id', 'workouts'),
    ]),
    CloudUploadTable('user_goals', [for (final g in uploadGoals) owned(g)]),
    CloudUploadTable('power_lift_records', [for (final p in powerLifts) owned(p)]),
  ];
  return CloudUploadPlan(
    tables,
    skipped,
    systemExerciseIds: cloudSystemExercises,
  );
}
