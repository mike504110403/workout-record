-- 畢業總審(security M1 + minor 4,2026-11-11)
--
-- 1. exercise_id 引用限「系統動作或本人動作」:
--    workout_exercises / template_exercises / personal_records 的 exercise_id FK
--    檢查不經 RLS,原本的 with check 只驗父列與 user_id,使用者可以把別人的
--    自建動作 id 寫進自己的列。後果:對方 delete_my_account cascade 刪 exercises
--    時撞 FK(NO ACTION)而整筆失敗,永遠刪不了帳號。
--    policy 子查詢讀 public.exercises 時套用 exercises_select(is_system 或本人),
--    別人的動作本來就看不到,exists 自然不成立。
-- 2. delete_workout_set 刪除限定 set 屬於 p_workout_exercise_id,避免刪 A 動作的組、
--    卻重編 B 動作的 set_number。

-- ---------- workout_exercises ----------
drop policy workout_exercises_insert on public.workout_exercises;
drop policy workout_exercises_update on public.workout_exercises;
create policy workout_exercises_insert on public.workout_exercises
  for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.workouts w
      where w.id = workout_id and w.user_id = (select auth.uid())
    )
    and exists (
      select 1 from public.exercises e
      where e.id = exercise_id and (e.is_system or e.user_id = (select auth.uid()))
    )
  );
create policy workout_exercises_update on public.workout_exercises
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.workouts w
      where w.id = workout_id and w.user_id = (select auth.uid())
    )
    and exists (
      select 1 from public.exercises e
      where e.id = exercise_id and (e.is_system or e.user_id = (select auth.uid()))
    )
  );

-- ---------- template_exercises ----------
drop policy template_exercises_insert on public.template_exercises;
drop policy template_exercises_update on public.template_exercises;
create policy template_exercises_insert on public.template_exercises
  for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.templates t
      where t.id = template_id and t.user_id = (select auth.uid()) and not t.is_system
    )
    and exists (
      select 1 from public.exercises e
      where e.id = exercise_id and (e.is_system or e.user_id = (select auth.uid()))
    )
  );
create policy template_exercises_update on public.template_exercises
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.templates t
      where t.id = template_id and t.user_id = (select auth.uid()) and not t.is_system
    )
    and exists (
      select 1 from public.exercises e
      where e.id = exercise_id and (e.is_system or e.user_id = (select auth.uid()))
    )
  );

-- ---------- personal_records(拆掉 for all,寫入另加 exercise 檢查)----------
drop policy personal_records_all on public.personal_records;
create policy personal_records_select on public.personal_records
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy personal_records_insert on public.personal_records
  for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.exercises e
      where e.id = exercise_id and (e.is_system or e.user_id = (select auth.uid()))
    )
  );
create policy personal_records_update on public.personal_records
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.exercises e
      where e.id = exercise_id and (e.is_system or e.user_id = (select auth.uid()))
    )
  );
create policy personal_records_delete on public.personal_records
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ---------- delete_workout_set:限定 set 屬於該 workout_exercise ----------
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

  delete from public.workout_sets s
  where s.id = p_set_id and s.workout_exercise_id = p_workout_exercise_id;
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
