-- Migration 0003 — RPC:Drift 版用單一 transaction 保證的多步寫入,在 Supabase 版收進
-- Postgres function(一次呼叫 = 一個 transaction)。
--
-- 一律 security invoker:函式內的讀寫照樣受 RLS 管,只是把多步操作綁成原子。
-- 擁有者欄位(user_id)一律由 auth.uid() 覆寫,不信任 client 傳入值。
--
-- 錯誤碼約定(app 端 supabase_mapping.dart 的 rethrowAsStateError 轉成 StateError,
-- 對齊 Drift 版拋 StateError 的語義):
--   P0002 = 找不到目標列(Drift 版 rowsAffected == 0 → StateError)
--   WR001 = 狀態不允許(例如對草稿呼叫 recompute)

-- ---------- 共用:批次插入 workout_exercises + workout_sets ----------
create or replace function public.insert_workout_children(
  p_exercises jsonb default '[]'::jsonb,
  p_sets jsonb default '[]'::jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  insert into public.workout_exercises
  select r.*
  from jsonb_populate_recordset(
    null::public.workout_exercises,
    (
      select jsonb_agg(e || jsonb_build_object('user_id', v_uid))
      from jsonb_array_elements(coalesce(p_exercises, '[]'::jsonb)) e
    )
  ) r;

  insert into public.workout_sets
  select r.*
  from jsonb_populate_recordset(
    null::public.workout_sets,
    (
      select jsonb_agg(s || jsonb_build_object('user_id', v_uid))
      from jsonb_array_elements(coalesce(p_sets, '[]'::jsonb)) s
    )
  ) r;
end;
$$;

-- ---------- 建立訓練(含 exercises/sets),對照 WorkoutRepository.create ----------
create or replace function public.create_workout(
  p_workout jsonb,
  p_exercises jsonb default '[]'::jsonb,
  p_sets jsonb default '[]'::jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  insert into public.workouts
  select r.*
  from jsonb_populate_record(
    null::public.workouts,
    p_workout || jsonb_build_object('user_id', v_uid)
  ) r;

  perform public.insert_workout_children(p_exercises, p_sets);
end;
$$;

-- ---------- 移除動作 + orderIndex 重編 0..N-1,對照 removeExercise ----------
create or replace function public.remove_workout_exercise(
  p_workout_exercise_id uuid,
  p_workout_id uuid
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- 鎖父列,讓同一筆訓練的「刪除 + 重編號」序列化,不被併發的另一次重編號插隊。
  perform 1 from public.workouts w where w.id = p_workout_id for update;

  delete from public.workout_exercises we
  where we.id = p_workout_exercise_id and we.workout_id = p_workout_id;
  if not found then
    raise exception 'WorkoutExercise not found: %', p_workout_exercise_id using errcode = 'P0002';
  end if;

  with ordered as (
    select we.id, (row_number() over (order by we.order_index, we.created_at, we.id) - 1)::int as rn
    from public.workout_exercises we
    where we.workout_id = p_workout_id
  )
  update public.workout_exercises we
  set order_index = o.rn
  from ordered o
  where we.id = o.id and we.order_index <> o.rn;
end;
$$;

-- ---------- 刪除組數 + setNumber 重編 1..N,對照 deleteSet ----------
create or replace function public.delete_workout_set(
  p_set_id uuid,
  p_workout_exercise_id uuid
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform 1 from public.workout_exercises we where we.id = p_workout_exercise_id for update;

  delete from public.workout_sets s where s.id = p_set_id;
  if not found then
    raise exception 'WorkoutSet not found: %', p_set_id using errcode = 'P0002';
  end if;

  with ordered as (
    select s.id, row_number() over (order by s.set_number, s.created_at, s.id)::int as rn
    from public.workout_sets s
    where s.workout_exercise_id = p_workout_exercise_id
  )
  update public.workout_sets s
  set set_number = o.rn
  from ordered o
  where s.id = o.id and s.set_number <> o.rn;
end;
$$;

-- ---------- 完成訓練,對照 completeWorkout ----------
-- 統計從 sets 現算,暖身組排除(對齊 nonWarmupTotalVolume/nonWarmupTotalSets);
-- duration = (ended - started) 的分鐘數,向零截斷(對齊 Dart Duration.inMinutes)。
-- DB 級冪等:UPDATE 帶 ended_at is null,已完成的訓練不會被覆寫。
create or replace function public.complete_workout(
  p_workout_id uuid,
  p_ended_at timestamptz default null
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_started_at timestamptz;
  v_ended_at timestamptz;
  v_total_volume double precision;
  v_total_sets integer;
  v_total_exercises integer;
begin
  select w.started_at into v_started_at
  from public.workouts w
  where w.id = p_workout_id
  for update;
  if not found then
    raise exception 'Workout not found: %', p_workout_id using errcode = 'P0002';
  end if;

  select
    coalesce(sum(s.weight * s.reps) filter (where not s.is_warmup), 0),
    (count(s.id) filter (where not s.is_warmup))::int
  into v_total_volume, v_total_sets
  from public.workout_exercises we
  join public.workout_sets s on s.workout_exercise_id = we.id
  where we.workout_id = p_workout_id;

  select count(*)::int into v_total_exercises
  from public.workout_exercises we
  where we.workout_id = p_workout_id;

  v_ended_at := coalesce(p_ended_at, now());

  update public.workouts w
  set ended_at = v_ended_at,
      duration = trunc(extract(epoch from (v_ended_at - v_started_at)) / 60)::int,
      total_volume = v_total_volume,
      total_sets = v_total_sets,
      total_exercises = v_total_exercises,
      updated_at = now(),
      is_synced = false
  where w.id = p_workout_id and w.ended_at is null;
end;
$$;

-- ---------- 編輯已完成訓練後重算 summary,對照 recomputeSummary ----------
-- 不動 ended_at/duration/started_at;會 bump updated_at;is_synced 不動。
create or replace function public.recompute_workout_summary(p_workout_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_ended_at timestamptz;
  v_total_volume double precision;
  v_total_sets integer;
  v_total_exercises integer;
begin
  select w.ended_at into v_ended_at
  from public.workouts w
  where w.id = p_workout_id
  for update;
  if not found then
    raise exception 'Workout not found: %', p_workout_id using errcode = 'P0002';
  end if;
  if v_ended_at is null then
    raise exception 'recomputeSummary: workout % 還是進行中的草稿(endedAt IS NULL),只有已完成的訓練才能重算 summary', p_workout_id
      using errcode = 'WR001';
  end if;

  select
    coalesce(sum(s.weight * s.reps) filter (where not s.is_warmup), 0),
    (count(s.id) filter (where not s.is_warmup))::int
  into v_total_volume, v_total_sets
  from public.workout_exercises we
  join public.workout_sets s on s.workout_exercise_id = we.id
  where we.workout_id = p_workout_id;

  select count(*)::int into v_total_exercises
  from public.workout_exercises we
  where we.workout_id = p_workout_id;

  update public.workouts w
  set total_volume = v_total_volume,
      total_sets = v_total_sets,
      total_exercises = v_total_exercises,
      updated_at = now()
  where w.id = p_workout_id and w.ended_at is not null;
end;
$$;

-- ---------- PR 結算:更高 1RM 才寫入,對照 createIfNewPR ----------
-- 以 (user, exercise) 的 advisory lock 序列化「查目前最高 → 比較 → 寫入」,
-- 多裝置同時結算同一動作不會各寫一筆。回傳 true = 已寫入新 PR。
create or replace function public.create_personal_record_if_new(p_record jsonb)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_exercise_id uuid := (p_record ->> 'exercise_id')::uuid;
  v_one_rep_max double precision := (p_record ->> 'one_rep_max')::double precision;
  v_current double precision;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('personal_records:' || v_uid::text || ':' || v_exercise_id::text, 0));

  select max(pr.one_rep_max) into v_current
  from public.personal_records pr
  where pr.user_id = v_uid and pr.exercise_id = v_exercise_id;

  if v_current is not null and not (v_one_rep_max > v_current) then
    return false;
  end if;

  insert into public.personal_records
  select r.*
  from jsonb_populate_record(
    null::public.personal_records,
    p_record || jsonb_build_object('user_id', v_uid)
  ) r;
  return true;
end;
$$;

-- ---------- 建立模板(含動作),對照 TemplateRepository.create ----------
create or replace function public.create_template(
  p_template jsonb,
  p_exercises jsonb default '[]'::jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  insert into public.templates
  select r.*
  from jsonb_populate_record(
    null::public.templates,
    p_template || jsonb_build_object('user_id', v_uid)
  ) r;

  insert into public.template_exercises
  select r.*
  from jsonb_populate_recordset(
    null::public.template_exercises,
    (
      select jsonb_agg(e || jsonb_build_object('user_id', v_uid, 'template_id', p_template ->> 'id'))
      from jsonb_array_elements(coalesce(p_exercises, '[]'::jsonb)) e
    )
  ) r;
end;
$$;

-- ---------- 更新模板 + 整批重建動作,對照 TemplateRepository.update ----------
create or replace function public.update_template(
  p_template_id uuid,
  p_name text,
  p_description_text text,
  p_exercises jsonb default '[]'::jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  update public.templates t
  set name = p_name,
      description_text = p_description_text,
      updated_at = now()
  where t.id = p_template_id;
  if not found then
    raise exception 'Template not found: %', p_template_id using errcode = 'P0002';
  end if;

  delete from public.template_exercises te where te.template_id = p_template_id;

  insert into public.template_exercises
  select r.*
  from jsonb_populate_recordset(
    null::public.template_exercises,
    (
      select jsonb_agg(e || jsonb_build_object('user_id', v_uid, 'template_id', p_template_id))
      from jsonb_array_elements(coalesce(p_exercises, '[]'::jsonb)) e
    )
  ) r;
end;
$$;

-- ---------- 授權:只給 authenticated ----------
revoke all on function public.insert_workout_children(jsonb, jsonb) from public, anon;
revoke all on function public.create_workout(jsonb, jsonb, jsonb) from public, anon;
revoke all on function public.remove_workout_exercise(uuid, uuid) from public, anon;
revoke all on function public.delete_workout_set(uuid, uuid) from public, anon;
revoke all on function public.complete_workout(uuid, timestamptz) from public, anon;
revoke all on function public.recompute_workout_summary(uuid) from public, anon;
revoke all on function public.create_personal_record_if_new(jsonb) from public, anon;
revoke all on function public.create_template(jsonb, jsonb) from public, anon;
revoke all on function public.update_template(uuid, text, text, jsonb) from public, anon;

grant execute on function public.insert_workout_children(jsonb, jsonb) to authenticated;
grant execute on function public.create_workout(jsonb, jsonb, jsonb) to authenticated;
grant execute on function public.remove_workout_exercise(uuid, uuid) to authenticated;
grant execute on function public.delete_workout_set(uuid, uuid) to authenticated;
grant execute on function public.complete_workout(uuid, timestamptz) to authenticated;
grant execute on function public.recompute_workout_summary(uuid) to authenticated;
grant execute on function public.create_personal_record_if_new(jsonb) to authenticated;
grant execute on function public.create_template(jsonb, jsonb) to authenticated;
grant execute on function public.update_template(uuid, text, text, jsonb) to authenticated;
