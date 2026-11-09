-- Migration 0001 — schema(對照 app/lib/data/db/tables.dart 的 11 張 Drift 表)
--
-- 型別對照:Drift TEXT(UUID)→ uuid、DateTime → timestamptz、real → double precision、
-- int → integer、bool → boolean。欄名為 Drift 產生的 SQL 欄名(snake_case),唯二例外
-- videoURL/imageURL:Drift 產生 video_u_r_l/image_u_r_l,這裡改叫 video_url/image_url
-- (app 端 supabase_mapping.dart 的 kDriftToPgColumn 負責轉換)。
--
-- 擁有權:每張使用者資料表都有 user_id uuid references auth.users。Drift 版的子表
-- (workout_exercises/workout_sets/template_exercises)本來沒有 user_id——這裡補上,
-- 預設 auth.uid(),讓 RLS 一律能寫成 `user_id = auth.uid()`;父子歸屬一致性由 RLS 的
-- with check 子查詢保證(見 0002)。
-- 系統動作/系統模板:is_system = true、user_id = null,只由 migration 寫入,全體唯讀共享。

-- ---------- users(個人資料,id 即 auth.users.id)----------
create table public.users (
  id uuid primary key references auth.users (id) on delete cascade,
  name text,
  email text,
  created_at timestamptz not null,
  updated_at timestamptz not null
);

-- ---------- exercises(系統動作 + 使用者自訂動作)----------
create table public.exercises (
  id uuid primary key,
  name text not null,
  name_en text,
  category_id text not null,
  type text not null,
  movement_pattern text,
  primary_muscle_group text,
  description_text text,
  video_url text,
  image_url text,
  is_system boolean not null default false,
  is_active boolean not null default true,
  -- 系統動作為 null。
  user_id uuid references auth.users (id) on delete cascade,
  created_at timestamptz not null,
  updated_at timestamptz not null
);
create index idx_exercises_user_id on public.exercises (user_id);
create index idx_exercises_is_system on public.exercises (is_system) where is_system;

-- ---------- body_weights ----------
create table public.body_weights (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  weight double precision not null default 0.0,
  measured_at timestamptz not null,
  note text,
  is_synced boolean not null default false,
  created_at timestamptz not null,
  updated_at timestamptz not null
);
create index idx_body_weights_user_id on public.body_weights (user_id);

-- ---------- workouts ----------
create table public.workouts (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  started_at timestamptz not null,
  -- null = 進行中草稿(草稿寫穿,見 .claude/decisions/2026-08-04-波3訓練流草稿寫穿與系統模板.md)
  ended_at timestamptz,
  duration integer default 0,
  total_volume double precision not null default 0.0,
  total_sets integer not null default 0,
  total_exercises integer not null default 0,
  note text,
  -- 故意不加 FK(同 Drift):舊資料的 denormalized UUID 會懸空,照抄保留原值。
  template_id uuid,
  is_synced boolean not null default false,
  created_at timestamptz not null,
  updated_at timestamptz not null
);
create index idx_workouts_user_id on public.workouts (user_id);
-- fetchDraft / 已完成清單都依 user_id + started_at 排序查詢。
create index idx_workouts_user_started_at on public.workouts (user_id, started_at desc);

-- ---------- workout_exercises ----------
create table public.workout_exercises (
  id uuid primary key,
  workout_id uuid not null references public.workouts (id) on delete cascade,
  -- 同 Drift:未設 onDelete(NO ACTION),見 app/lib/data/db/README.md review 追蹤事項。
  exercise_id uuid not null references public.exercises (id),
  exercise_name text,
  order_index integer not null default 0,
  total_volume double precision not null default 0.0,
  total_sets integer not null default 0,
  is_completed boolean not null default false,
  is_custom_exercise boolean not null default false,
  note text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade
);
create index idx_workout_exercises_workout_id on public.workout_exercises (workout_id);
create index idx_workout_exercises_exercise_id on public.workout_exercises (exercise_id);
create index idx_workout_exercises_user_id on public.workout_exercises (user_id);

-- ---------- workout_sets ----------
create table public.workout_sets (
  id uuid primary key,
  workout_exercise_id uuid not null references public.workout_exercises (id) on delete cascade,
  set_number integer not null default 0,
  weight double precision not null default 0.0,
  reps integer not null default 0,
  volume double precision not null default 0.0,
  rpe double precision default 0.0,
  rest_seconds integer default 0,
  is_warmup boolean not null default false,
  note text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade
);
create index idx_workout_sets_workout_exercise_id on public.workout_sets (workout_exercise_id);
create index idx_workout_sets_user_id on public.workout_sets (user_id);

-- ---------- templates(系統模板 + 使用者模板)----------
create table public.templates (
  id uuid primary key,
  -- 系統模板為 null(對齊 Drift schemaVersion 2 的 nullable 調整)。
  user_id uuid references auth.users (id) on delete cascade,
  name text not null,
  description_text text,
  is_system boolean not null default false,
  created_at timestamptz not null,
  updated_at timestamptz not null
);
create index idx_templates_user_id on public.templates (user_id);

-- ---------- template_exercises ----------
create table public.template_exercises (
  id uuid primary key,
  template_id uuid not null references public.templates (id) on delete cascade,
  exercise_id uuid not null references public.exercises (id),
  order_index integer not null default 0,
  suggested_sets integer default 0,
  suggested_reps integer default 0,
  -- 系統模板的動作為 null;使用者模板的動作預設 auth.uid()。
  user_id uuid default auth.uid() references auth.users (id) on delete cascade
);
create index idx_template_exercises_template_id on public.template_exercises (template_id);
create index idx_template_exercises_exercise_id on public.template_exercises (exercise_id);
create index idx_template_exercises_user_id on public.template_exercises (user_id);

-- ---------- personal_records ----------
create table public.personal_records (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  exercise_id uuid not null references public.exercises (id),
  one_rep_max double precision not null default 0.0,
  weight double precision not null default 0.0,
  reps integer not null default 0,
  achieved_at timestamptz not null,
  -- 故意不加 FK(同 Drift):舊資料的 denormalized UUID 會懸空,照抄保留原值。
  workout_id uuid,
  created_at timestamptz not null,
  updated_at timestamptz not null
);
create index idx_personal_records_user_id on public.personal_records (user_id);
create index idx_personal_records_exercise_id on public.personal_records (exercise_id);

-- ---------- user_goals(每位使用者一筆)----------
create table public.user_goals (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  target_weight double precision default 0.0,
  weekly_workout_goal integer not null default 0,
  chest_volume_goal double precision default 0.0,
  back_volume_goal double precision default 0.0,
  legs_volume_goal double precision default 0.0,
  shoulders_volume_goal double precision default 0.0,
  arms_volume_goal double precision default 0.0,
  core_volume_goal double precision default 0.0,
  rest_day_reminder boolean not null default false,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  -- Drift 版沒有這道約束,只靠 repository「先查再寫」維持一人一筆;雲端多裝置
  -- 併發下補上 DB 級保證(fetchByUser 用 maybeSingle,多筆會直接炸)。
  constraint user_goals_user_id_key unique (user_id)
);

-- ---------- power_lift_records ----------
create table public.power_lift_records (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  lift text not null,
  one_rep_max double precision not null default 0.0,
  weight double precision not null default 0.0,
  reps integer not null default 1,
  achieved_at timestamptz not null,
  note text,
  created_at timestamptz not null,
  updated_at timestamptz not null
);
create index idx_power_lift_records_user_id on public.power_lift_records (user_id);
