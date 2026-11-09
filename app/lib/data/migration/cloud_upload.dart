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
// 中途失敗不寫旗標,下次啟動或設定頁重試會從頭再跑一次(已上傳的列被忽略)。
import 'package:drift/drift.dart' show Expression, Insertable, Variable;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/app_database.dart';

/// 依 auth uid 區分的「已上傳完成」旗標 key。
String cloudUploadCompletedKey(String uid) => 'cloud_upload_completed_$uid';

/// 一次性上傳的結果。
class CloudUploadResult {
  const CloudUploadResult({
    required this.success,
    this.skipped = false,
    this.uploadedRows = 0,
    this.tableCounts = const {},
    this.skippedCounts = const {},
    this.errorMessage,
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

  final String? errorMessage;
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
}

/// 本機 Drift 資料一次性上傳到 Supabase(登入後呼叫)。
abstract interface class LocalToCloudUploader {
  /// [uid] 是否已上傳完成(旗標已寫)。
  bool isCompleted(String uid);

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
  DriftToSupabaseUploader({required SharedPreferences prefs, this.batchSize = 500})
      : _prefs = prefs,
        assert(batchSize > 0);

  final SharedPreferences _prefs;

  /// 每次 PostgREST 請求最多送幾列。
  final int batchSize;

  @override
  bool isCompleted(String uid) => _prefs.getBool(cloudUploadCompletedKey(uid)) ?? false;

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
        return const CloudUploadResult(success: false, errorMessage: '尚未登入,無法上傳');
      }
      if (isCompleted(uid)) {
        return const CloudUploadResult(success: true, skipped: true);
      }
      if (ensureUser != null) {
        await sink.ensureUser(uid, ensureUser);
      }
      if (!await hasUploadableData(local)) {
        return const CloudUploadResult(success: true, skipped: true);
      }

      final plan = await buildCloudUploadPlan(local, sink, uid);
      final counts = <String, int>{};
      for (final entry in plan.tables) {
        final rows = entry.rows;
        for (var i = 0; i < rows.length; i += batchSize) {
          final end = i + batchSize < rows.length ? i + batchSize : rows.length;
          await sink.insertIgnoringDuplicates(entry.table, rows.sublist(i, end));
        }
        counts[entry.table] = rows.length;
      }

      await _prefs.setBool(cloudUploadCompletedKey(uid), true);
      return CloudUploadResult(
        success: true,
        uploadedRows: counts.values.fold(0, (a, b) => a + b),
        tableCounts: counts,
        skippedCounts: plan.skippedCounts,
      );
    } catch (e) {
      return CloudUploadResult(success: false, errorMessage: '$e');
    }
  }
}

/// 一張表要送出的列(已套用對應規則)。
class CloudUploadTable {
  const CloudUploadTable(this.table, this.rows);

  final String table;
  final List<Map<String, dynamic>> rows;
}

/// 上傳計畫:[tables] 依父子順序排列。
class CloudUploadPlan {
  const CloudUploadPlan(this.tables, this.skippedCounts);

  final List<CloudUploadTable> tables;
  final Map<String, int> skippedCounts;

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
    final cloudHasOtherDraft = cloudDrafts.any((id) => id != keep.id);
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
    if (cloudGoalId == null || cloudGoalId == latest.id) {
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
    ]),
    CloudUploadTable('workouts', [
      for (final w in uploadWorkouts)
        owned(w)..['template_id'] = w.templateId == null ? null : (templateIdMap[w.templateId] ?? w.templateId),
    ]),
    CloudUploadTable('workout_exercises', [
      for (final we in uploadWorkoutExercises) owned(we)..['exercise_id'] = mapExercise(we.exerciseId),
    ]),
    CloudUploadTable('workout_sets', [for (final s in uploadWorkoutSets) owned(s)]),
    CloudUploadTable('body_weights', [for (final b in bodyWeights) owned(b)]),
    CloudUploadTable('personal_records', [
      for (final pr in personalRecords) owned(pr)..['exercise_id'] = mapExercise(pr.exerciseId),
    ]),
    CloudUploadTable('user_goals', [for (final g in uploadGoals) owned(g)]),
    CloudUploadTable('power_lift_records', [for (final p in powerLifts) owned(p)]),
  ];
  return CloudUploadPlan(tables, skipped);
}
