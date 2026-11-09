// 從 `lib/data/db/seed_data.dart` 產生 Supabase 的系統動作/系統模板種子
// migration(`supabase/migrations/20261110000400_seed_system_data.sql`)。
//
// seed_data.dart 依賴 flutter(debugPrint),所以用 flutter test 跑:
//
//   cd app && flutter test tool/gen_supabase_seed.dart
//
// 種子內容(kSeedExercises / kSeedTemplates)有改時重跑本工具,**另開一個新的
// migration 檔**補差異(已套用過的 migration 不可改寫);本工具只負責產生
// 初始那一份。
//
// id 策略:Drift 版每次安裝隨機產生 id、以「名稱」當穩定鍵(見 seed_data.dart
// 開頭說明)。Supabase 版的系統資料是全體使用者共享的單一份,改用
// `md5(穩定鍵)::uuid` 的確定性 id,讓 migration 可重跑(on conflict do nothing)、
// 各環境(本機/dev/prod)的系統動作 id 一致。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/data/db/seed_data.dart';

String _lit(String? value) => value == null ? 'null' : "'${value.replaceAll("'", "''")}'";

String _int(int? value) => value == null ? 'null' : '$value';

void main() {
  test('generate supabase seed migration', () {
    final out = StringBuffer()
      ..writeln('-- Migration 0004 — 系統動作庫 + 五套系統模板種子')
      ..writeln('-- 由 app/tool/gen_supabase_seed.dart 從 app/lib/data/db/seed_data.dart 產生,勿手改;')
      ..writeln('-- 種子有變動時另開新 migration 補差異。')
      ..writeln('-- id 用 md5(穩定鍵)::uuid 確定性產生(見產生器檔頭說明),可重跑。')
      ..writeln()
      ..writeln('-- ---------- 系統動作(${kSeedExercises.length} 筆)----------')
      ..writeln('insert into public.exercises (')
      ..writeln('  id, name, name_en, category_id, type, movement_pattern, primary_muscle_group,')
      ..writeln('  is_system, is_active, user_id, created_at, updated_at')
      ..writeln(')')
      ..writeln('select')
      ..writeln("  md5('workout-record/system-exercise/' || v.category_id || '/' || v.name)::uuid,")
      ..writeln('  v.name, v.name_en, v.category_id, v.type, v.movement_pattern, v.primary_muscle_group,')
      ..writeln('  true, true, null, now(), now()')
      ..writeln('from (values');
    for (var i = 0; i < kSeedExercises.length; i++) {
      final e = kSeedExercises[i];
      final sep = i == kSeedExercises.length - 1 ? '' : ',';
      out.writeln('  (${_lit(e.name)}, ${_lit(e.nameEn)}, ${_lit(e.categoryId)}, ${_lit(e.type)}, '
          '${_lit(e.movementPattern)}, ${_lit(e.primaryMuscleGroup)})$sep');
    }
    out
      ..writeln(') as v(name, name_en, category_id, type, movement_pattern, primary_muscle_group)')
      ..writeln('on conflict (id) do nothing;')
      ..writeln()
      ..writeln('-- ---------- 系統模板(${kSeedTemplates.length} 套)----------')
      ..writeln('insert into public.templates (id, user_id, name, description_text, is_system, created_at, updated_at)')
      ..writeln('select')
      ..writeln("  md5('workout-record/system-template/' || v.name)::uuid,")
      ..writeln('  null, v.name, v.description_text, true, now(), now()')
      ..writeln('from (values');
    for (var i = 0; i < kSeedTemplates.length; i++) {
      final t = kSeedTemplates[i];
      final sep = i == kSeedTemplates.length - 1 ? '' : ',';
      out.writeln('  (${_lit(t.name)}, ${_lit(t.description)})$sep');
    }
    out
      ..writeln(') as v(name, description_text)')
      ..writeln('on conflict (id) do nothing;')
      ..writeln()
      ..writeln('-- 模板動作:以動作「名稱」對應系統動作。撞名(硬舉、臉拉跨分類重複)時')
      ..writeln('-- 取 category_id 最小的那筆,對齊 Drift 版 _seedSystemTemplatesIfEmpty 的')
      ..writeln('-- 「依 categoryId 排序 + putIfAbsent」規則(背部先於腿部)。')
      ..writeln('insert into public.template_exercises (')
      ..writeln('  id, template_id, exercise_id, order_index, suggested_sets, suggested_reps, user_id')
      ..writeln(')')
      ..writeln('select')
      ..writeln("  md5('workout-record/system-template-exercise/' || v.template_name || '/' || v.order_index)::uuid,")
      ..writeln("  md5('workout-record/system-template/' || v.template_name)::uuid,")
      ..writeln('  (')
      ..writeln('    select e.id from public.exercises e')
      ..writeln('    where e.is_system and e.name = v.exercise_name')
      ..writeln('    order by e.category_id')
      ..writeln('    limit 1')
      ..writeln('  ),')
      ..writeln('  v.order_index, v.suggested_sets, v.suggested_reps, null')
      ..writeln('from (values');
    final rows = <String>[];
    for (final t in kSeedTemplates) {
      for (var i = 0; i < t.exercises.length; i++) {
        final e = t.exercises[i];
        rows.add('  (${_lit(t.name)}, $i, ${_lit(e.exerciseName)}, '
            '${_int(e.suggestedSets)}, ${_int(e.suggestedReps)})');
      }
    }
    out
      ..writeln(rows.join(',\n'))
      ..writeln(') as v(template_name, order_index, exercise_name, suggested_sets, suggested_reps)')
      ..writeln('on conflict (id) do nothing;');

    File('../supabase/migrations/20261110000400_seed_system_data.sql')
      ..createSync(recursive: true)
      ..writeAsStringSync(out.toString());
  });
}
