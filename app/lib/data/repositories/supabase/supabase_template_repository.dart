import 'package:drift/drift.dart' show Value;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/exercise.dart';
import '../../models/workout_template.dart';
import '../template_repository.dart';
import 'supabase_mapping.dart';

/// [TemplateRepository] 的 Supabase 實作。
///
/// 與 [DriftTemplateRepository] 的差異:
/// - 系統模板全體共享唯讀(RLS);使用者模板只有本人看得到。[fetchAll] 的
///   userId 參數不參與查詢,寫入的 `user_id` 一律是登入者 auth uid。
/// - [create]/[update] 走 RPC(`create_template`/`update_template`),模板與其
///   動作的寫入/整批重建在同一個 transaction 內,對齊 Drift 版的 transaction。
/// - [update] 對系統模板不生效:RLS 擋下 → RPC 視為找不到 → StateError
///   (Drift 版沒有擋,系統模板也能改名)。
/// - `updated_at` 由 DB `now()` 決定(Drift 版用 client 時鐘)。
class SupabaseTemplateRepository implements TemplateRepository {
  SupabaseTemplateRepository(this._client);

  final SupabaseClient _client;

  static const _select = '*, template_exercises(*, exercises(*))';

  SupabaseQueryBuilder get _table => _client.from('templates');

  @override
  Future<void> create(WorkoutTemplate template) async {
    requireUid(_client);
    final exercises = [
      for (var i = 0; i < template.exercises.length; i++)
        companionToJson(template.exercises[i].toCompanion().copyWith(
              templateId: Value(template.id),
              orderIndex: Value(i),
            )),
    ];
    await _client.rpc<void>('create_template', params: {
      'p_template': companionToJson(template.toCompanion()),
      'p_exercises': exercises,
    });
  }

  @override
  Future<List<WorkoutTemplate>> fetchAll(String userId) async {
    final rows = await _table
        .select(_select)
        .eq('user_id', requireUid(_client))
        .eq('is_system', false)
        .order('name', ascending: true);
    return rows.map(_hydrate).toList();
  }

  @override
  Future<WorkoutTemplate?> fetchById(String id) async {
    final row = await _table.select(_select).eq('id', id).maybeSingle();
    return row == null ? null : _hydrate(row);
  }

  @override
  Future<List<WorkoutTemplate>> fetchSystemTemplates() async {
    final rows = await _table.select(_select).eq('is_system', true).order('name', ascending: true);
    return rows.map(_hydrate).toList();
  }

  @override
  Future<void> update(WorkoutTemplate template) async {
    final exercises = [
      for (var i = 0; i < template.exercises.length; i++)
        {
          'id': template.exercises[i].id,
          'exercise_id': template.exercises[i].exerciseId,
          'order_index': i,
          'suggested_sets': template.exercises[i].suggestedSets,
          'suggested_reps': template.exercises[i].suggestedReps,
        },
    ];
    await rethrowAsStateError(() => _client.rpc<void>('update_template', params: {
          'p_template_id': template.id,
          'p_name': template.name,
          'p_description_text': template.description,
          'p_exercises': exercises,
        }));
  }

  @override
  Future<void> delete(String id) async {
    await _table.delete().eq('id', id).eq('is_system', false);
  }

  WorkoutTemplate _hydrate(Map<String, dynamic> row) {
    final children = [
      for (final child in (row['template_exercises'] as List? ?? const []))
        Map<String, dynamic>.from(child as Map),
    ]..sort((a, b) => (a['order_index'] as num).compareTo(b['order_index'] as num));

    final exercises = <TemplateExercise>[];
    for (final child in children) {
      final exerciseJson = child['exercises'];
      final Exercise? exercise = exerciseJson is Map<String, dynamic>
          ? Exercise.fromRow(exerciseRowFromJson(exerciseJson))
          : null;
      exercises.add(TemplateExercise.fromRow(templateExerciseRowFromJson(child), exercise: exercise));
    }
    return WorkoutTemplate.fromRow(templateRowFromJson(row), exercises: exercises);
  }
}
