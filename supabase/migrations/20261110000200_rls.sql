-- Migration 0002 — RLS + 授權
--
-- 原則:使用者資料只有本人看得到、寫得動(auth.uid() = user_id);
-- 系統動作/系統模板(is_system = true、user_id = null)全體 authenticated 唯讀共享,
-- 只能由 migration(postgres 角色,繞過 RLS)寫入。
-- 子表(workout_exercises/workout_sets/template_exercises)寫入時另以子查詢確認
-- 父列也屬於本人,避免把自己的子列掛到別人的父列底下(FK 檢查不經過 RLS)。
--
-- 雲端專案已關閉「新表自動 expose」、已開 automatic RLS;這裡不倚賴兩者,
-- 明確 enable RLS + 明確 GRANT,並收回本機 CLI 預設權限給 anon 的部分。

-- ---------- enable RLS ----------
alter table public.users enable row level security;
alter table public.exercises enable row level security;
alter table public.body_weights enable row level security;
alter table public.workouts enable row level security;
alter table public.workout_exercises enable row level security;
alter table public.workout_sets enable row level security;
alter table public.templates enable row level security;
alter table public.template_exercises enable row level security;
alter table public.personal_records enable row level security;
alter table public.user_goals enable row level security;
alter table public.power_lift_records enable row level security;

-- ---------- 授權 ----------
revoke all on
  public.users, public.exercises, public.body_weights, public.workouts,
  public.workout_exercises, public.workout_sets, public.templates,
  public.template_exercises, public.personal_records, public.user_goals,
  public.power_lift_records
from anon, authenticated, public;

grant usage on schema public to authenticated;
grant select, insert, update, delete on
  public.users, public.exercises, public.body_weights, public.workouts,
  public.workout_exercises, public.workout_sets, public.templates,
  public.template_exercises, public.personal_records, public.user_goals,
  public.power_lift_records
to authenticated;

-- ---------- users ----------
create policy users_select on public.users
  for select to authenticated using ((select auth.uid()) = id);
create policy users_insert on public.users
  for insert to authenticated with check ((select auth.uid()) = id);
create policy users_update on public.users
  for update to authenticated
  using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create policy users_delete on public.users
  for delete to authenticated using ((select auth.uid()) = id);

-- ---------- exercises(系統唯讀共享)----------
create policy exercises_select on public.exercises
  for select to authenticated
  using (is_system or (select auth.uid()) = user_id);
create policy exercises_insert on public.exercises
  for insert to authenticated
  with check ((select auth.uid()) = user_id and not is_system);
create policy exercises_update on public.exercises
  for update to authenticated
  using ((select auth.uid()) = user_id and not is_system)
  with check ((select auth.uid()) = user_id and not is_system);
create policy exercises_delete on public.exercises
  for delete to authenticated
  using ((select auth.uid()) = user_id and not is_system);

-- ---------- templates(系統唯讀共享)----------
create policy templates_select on public.templates
  for select to authenticated
  using (is_system or (select auth.uid()) = user_id);
create policy templates_insert on public.templates
  for insert to authenticated
  with check ((select auth.uid()) = user_id and not is_system);
create policy templates_update on public.templates
  for update to authenticated
  using ((select auth.uid()) = user_id and not is_system)
  with check ((select auth.uid()) = user_id and not is_system);
create policy templates_delete on public.templates
  for delete to authenticated
  using ((select auth.uid()) = user_id and not is_system);

-- ---------- template_exercises(系統模板的動作唯讀共享)----------
create policy template_exercises_select on public.template_exercises
  for select to authenticated
  using (
    (select auth.uid()) = user_id
    or (
      user_id is null
      and exists (
        select 1 from public.templates t
        where t.id = template_id and t.is_system
      )
    )
  );
create policy template_exercises_insert on public.template_exercises
  for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.templates t
      where t.id = template_id and t.user_id = (select auth.uid()) and not t.is_system
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
  );
create policy template_exercises_delete on public.template_exercises
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ---------- 單純本人擁有的表 ----------
-- body_weights / workouts / personal_records / user_goals / power_lift_records
create policy body_weights_all on public.body_weights
  for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy workouts_all on public.workouts
  for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy personal_records_all on public.personal_records
  for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy user_goals_all on public.user_goals
  for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy power_lift_records_all on public.power_lift_records
  for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- ---------- workout_exercises(父 workout 必須是本人的)----------
create policy workout_exercises_select on public.workout_exercises
  for select to authenticated using ((select auth.uid()) = user_id);
create policy workout_exercises_insert on public.workout_exercises
  for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.workouts w
      where w.id = workout_id and w.user_id = (select auth.uid())
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
  );
create policy workout_exercises_delete on public.workout_exercises
  for delete to authenticated using ((select auth.uid()) = user_id);

-- ---------- workout_sets(父 workout_exercise 必須是本人的)----------
create policy workout_sets_select on public.workout_sets
  for select to authenticated using ((select auth.uid()) = user_id);
create policy workout_sets_insert on public.workout_sets
  for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.workout_exercises we
      where we.id = workout_exercise_id and we.user_id = (select auth.uid())
    )
  );
create policy workout_sets_update on public.workout_sets
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.workout_exercises we
      where we.id = workout_exercise_id and we.user_id = (select auth.uid())
    )
  );
create policy workout_sets_delete on public.workout_sets
  for delete to authenticated using ((select auth.uid()) = user_id);
