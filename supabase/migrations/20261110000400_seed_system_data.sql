-- Migration 0004 — 系統動作庫 + 五套系統模板種子
-- 由 app/tool/gen_supabase_seed.dart 從 app/lib/data/db/seed_data.dart 產生,勿手改;
-- 種子有變動時另開新 migration 補差異。
-- id 用 md5(穩定鍵)::uuid 確定性產生(見產生器檔頭說明),可重跑。

-- ---------- 系統動作(66 筆)----------
insert into public.exercises (
  id, name, name_en, category_id, type, movement_pattern, primary_muscle_group,
  is_system, is_active, user_id, created_at, updated_at
)
select
  md5('workout-record/system-exercise/' || v.category_id || '/' || v.name)::uuid,
  v.name, v.name_en, v.category_id, v.type, v.movement_pattern, v.primary_muscle_group,
  true, true, null, now(), now()
from (values
  ('槓鈴臥推', 'Barbell Bench Press', '00000000-0000-0000-0000-000000000001', 'free_weight', 'push', 'chest'),
  ('啞鈴臥推', 'Dumbbell Bench Press', '00000000-0000-0000-0000-000000000001', 'free_weight', 'push', 'chest'),
  ('上斜槓鈴臥推', 'Incline Barbell Press', '00000000-0000-0000-0000-000000000001', 'free_weight', 'push', 'chest'),
  ('上斜啞鈴臥推', 'Incline Dumbbell Press', '00000000-0000-0000-0000-000000000001', 'free_weight', 'push', 'chest'),
  ('下斜槓鈴臥推', 'Decline Barbell Press', '00000000-0000-0000-0000-000000000001', 'free_weight', 'push', 'chest'),
  ('啞鈴飛鳥', 'Dumbbell Fly', '00000000-0000-0000-0000-000000000001', 'free_weight', 'isolation', 'chest'),
  ('上斜啞鈴飛鳥', 'Incline Dumbbell Fly', '00000000-0000-0000-0000-000000000001', 'free_weight', 'isolation', 'chest'),
  ('胸推機', 'Chest Press Machine', '00000000-0000-0000-0000-000000000001', 'machine', 'push', 'chest'),
  ('蝴蝶機', 'Pec Deck Fly', '00000000-0000-0000-0000-000000000001', 'machine', 'isolation', 'chest'),
  ('Cable 飛鳥', 'Cable Crossover', '00000000-0000-0000-0000-000000000001', 'machine', 'isolation', 'chest'),
  ('伏地挺身', 'Push-up', '00000000-0000-0000-0000-000000000001', 'bodyweight', 'push', 'chest'),
  ('雙槓撐體', 'Dips', '00000000-0000-0000-0000-000000000001', 'bodyweight', 'push', 'chest'),
  ('硬舉', 'Deadlift', '00000000-0000-0000-0000-000000000002', 'free_weight', 'pull', 'back'),
  ('槓鈴划船', 'Barbell Row', '00000000-0000-0000-0000-000000000002', 'free_weight', 'pull', 'back'),
  ('啞鈴划船', 'Dumbbell Row', '00000000-0000-0000-0000-000000000002', 'free_weight', 'pull', 'back'),
  ('T 槓划船', 'T-Bar Row', '00000000-0000-0000-0000-000000000002', 'free_weight', 'pull', 'back'),
  ('引體向上', 'Pull-up', '00000000-0000-0000-0000-000000000002', 'bodyweight', 'pull', 'back'),
  ('滑輪下拉', 'Lat Pulldown', '00000000-0000-0000-0000-000000000002', 'machine', 'pull', 'back'),
  ('坐姿划船', 'Seated Cable Row', '00000000-0000-0000-0000-000000000002', 'machine', 'pull', 'back'),
  ('單臂啞鈴划船', 'One-Arm Dumbbell Row', '00000000-0000-0000-0000-000000000002', 'free_weight', 'pull', 'back'),
  ('直臂下壓', 'Straight Arm Pulldown', '00000000-0000-0000-0000-000000000002', 'machine', 'isolation', 'back'),
  ('臉拉', 'Face Pull', '00000000-0000-0000-0000-000000000002', 'machine', 'pull', 'shoulders'),
  ('反向飛鳥', 'Reverse Fly', '00000000-0000-0000-0000-000000000002', 'free_weight', 'isolation', 'shoulders'),
  ('深蹲', 'Squat', '00000000-0000-0000-0000-000000000003', 'free_weight', 'squat', 'legs'),
  ('前蹲', 'Front Squat', '00000000-0000-0000-0000-000000000003', 'free_weight', 'squat', 'legs'),
  ('硬舉', 'Deadlift', '00000000-0000-0000-0000-000000000003', 'free_weight', 'hinge', 'legs'),
  ('羅馬尼亞硬舉', 'Romanian Deadlift', '00000000-0000-0000-0000-000000000003', 'free_weight', 'hinge', 'legs'),
  ('腿推機', 'Leg Press', '00000000-0000-0000-0000-000000000003', 'machine', 'squat', 'legs'),
  ('腿伸屈', 'Leg Extension', '00000000-0000-0000-0000-000000000003', 'machine', 'isolation', 'legs'),
  ('腿彎舉', 'Leg Curl', '00000000-0000-0000-0000-000000000003', 'machine', 'isolation', 'legs'),
  ('保加利亞分腿蹲', 'Bulgarian Split Squat', '00000000-0000-0000-0000-000000000003', 'free_weight', 'squat', 'legs'),
  ('箭步蹲', 'Lunge', '00000000-0000-0000-0000-000000000003', 'free_weight', 'squat', 'legs'),
  ('臀推', 'Hip Thrust', '00000000-0000-0000-0000-000000000003', 'free_weight', 'hinge', 'legs'),
  ('提踵', 'Calf Raise', '00000000-0000-0000-0000-000000000003', 'free_weight', 'isolation', 'legs'),
  ('坐姿提踵', 'Seated Calf Raise', '00000000-0000-0000-0000-000000000003', 'machine', 'isolation', 'legs'),
  ('肩推', 'Overhead Press', '00000000-0000-0000-0000-000000000004', 'free_weight', 'push', 'shoulders'),
  ('啞鈴肩推', 'Dumbbell Shoulder Press', '00000000-0000-0000-0000-000000000004', 'free_weight', 'push', 'shoulders'),
  ('阿諾推舉', 'Arnold Press', '00000000-0000-0000-0000-000000000004', 'free_weight', 'push', 'shoulders'),
  ('側平舉', 'Lateral Raise', '00000000-0000-0000-0000-000000000004', 'free_weight', 'isolation', 'shoulders'),
  ('前平舉', 'Front Raise', '00000000-0000-0000-0000-000000000004', 'free_weight', 'isolation', 'shoulders'),
  ('俯身側平舉', 'Bent-Over Lateral Raise', '00000000-0000-0000-0000-000000000004', 'free_weight', 'isolation', 'shoulders'),
  ('直立划船', 'Upright Row', '00000000-0000-0000-0000-000000000004', 'free_weight', 'pull', 'shoulders'),
  ('肩推機', 'Shoulder Press Machine', '00000000-0000-0000-0000-000000000004', 'machine', 'push', 'shoulders'),
  ('Cable 側平舉', 'Cable Lateral Raise', '00000000-0000-0000-0000-000000000004', 'machine', 'isolation', 'shoulders'),
  ('臉拉', 'Face Pull', '00000000-0000-0000-0000-000000000004', 'machine', 'pull', 'shoulders'),
  ('槓鈴彎舉', 'Barbell Curl', '00000000-0000-0000-0000-000000000005', 'free_weight', 'pull', 'arms'),
  ('啞鈴彎舉', 'Dumbbell Curl', '00000000-0000-0000-0000-000000000005', 'free_weight', 'pull', 'arms'),
  ('錘式彎舉', 'Hammer Curl', '00000000-0000-0000-0000-000000000005', 'free_weight', 'pull', 'arms'),
  ('集中彎舉', 'Concentration Curl', '00000000-0000-0000-0000-000000000005', 'free_weight', 'isolation', 'arms'),
  ('三頭下壓', 'Tricep Pushdown', '00000000-0000-0000-0000-000000000005', 'machine', 'push', 'arms'),
  ('過頭三頭伸展', 'Overhead Tricep Extension', '00000000-0000-0000-0000-000000000005', 'free_weight', 'isolation', 'arms'),
  ('窄握臥推', 'Close-Grip Bench Press', '00000000-0000-0000-0000-000000000005', 'free_weight', 'push', 'arms'),
  ('啞鈴三頭後踢', 'Tricep Kickback', '00000000-0000-0000-0000-000000000005', 'free_weight', 'isolation', 'arms'),
  ('Cable 彎舉', 'Cable Curl', '00000000-0000-0000-0000-000000000005', 'machine', 'pull', 'arms'),
  ('EZ Bar 彎舉', 'EZ Bar Curl', '00000000-0000-0000-0000-000000000005', 'free_weight', 'pull', 'arms'),
  ('反握彎舉', 'Reverse Curl', '00000000-0000-0000-0000-000000000005', 'free_weight', 'pull', 'arms'),
  ('捲腹', 'Crunch', '00000000-0000-0000-0000-000000000006', 'bodyweight', 'isolation', 'core'),
  ('仰臥起坐', 'Sit-up', '00000000-0000-0000-0000-000000000006', 'bodyweight', 'isolation', 'core'),
  ('棒式', 'Plank', '00000000-0000-0000-0000-000000000006', 'bodyweight', 'isolation', 'core'),
  ('側棒式', 'Side Plank', '00000000-0000-0000-0000-000000000006', 'bodyweight', 'isolation', 'core'),
  ('懸吊舉腿', 'Hanging Leg Raise', '00000000-0000-0000-0000-000000000006', 'bodyweight', 'isolation', 'core'),
  ('捲腹機', 'Ab Crunch Machine', '00000000-0000-0000-0000-000000000006', 'machine', 'isolation', 'core'),
  ('Cable 捲腹', 'Cable Crunch', '00000000-0000-0000-0000-000000000006', 'machine', 'isolation', 'core'),
  ('Russian Twist', 'Russian Twist', '00000000-0000-0000-0000-000000000006', 'bodyweight', 'isolation', 'core'),
  ('登山者式', 'Mountain Climber', '00000000-0000-0000-0000-000000000006', 'bodyweight', 'isolation', 'core'),
  ('腹輪', 'Ab Wheel', '00000000-0000-0000-0000-000000000006', 'bodyweight', 'isolation', 'core')
) as v(name, name_en, category_id, type, movement_pattern, primary_muscle_group)
on conflict (id) do nothing;

-- ---------- 系統模板(5 套)----------
insert into public.templates (id, user_id, name, description_text, is_system, created_at, updated_at)
select
  md5('workout-record/system-template/' || v.name)::uuid,
  null, v.name, v.description_text, true, now(), now()
from (values
  ('PPL - Push (推)', '胸、肩、三頭訓練'),
  ('PPL - Pull (拉)', '背、二頭訓練'),
  ('PPL - Legs (腿)', '腿部完整訓練'),
  ('上肢訓練', '上半身完整訓練'),
  ('全身訓練', '適合初學者的全身訓練')
) as v(name, description_text)
on conflict (id) do nothing;

-- 模板動作:以動作「名稱」對應系統動作。撞名(硬舉、臉拉跨分類重複)時
-- 取 category_id 最小的那筆,對齊 Drift 版 _seedSystemTemplatesIfEmpty 的
-- 「依 categoryId 排序 + putIfAbsent」規則(背部先於腿部)。
insert into public.template_exercises (
  id, template_id, exercise_id, order_index, suggested_sets, suggested_reps, user_id
)
select
  md5('workout-record/system-template-exercise/' || v.template_name || '/' || v.order_index)::uuid,
  md5('workout-record/system-template/' || v.template_name)::uuid,
  (
    select e.id from public.exercises e
    where e.is_system and e.name = v.exercise_name
    order by e.category_id
    limit 1
  ),
  v.order_index, v.suggested_sets, v.suggested_reps, null
from (values
  ('PPL - Push (推)', 0, '槓鈴臥推', 4, 8),
  ('PPL - Push (推)', 1, '上斜啞鈴臥推', 4, 10),
  ('PPL - Push (推)', 2, '肩推', 4, 10),
  ('PPL - Push (推)', 3, '側平舉', 3, 12),
  ('PPL - Push (推)', 4, '三頭下壓', 3, 12),
  ('PPL - Pull (拉)', 0, '硬舉', 3, 5),
  ('PPL - Pull (拉)', 1, '引體向上', 4, 8),
  ('PPL - Pull (拉)', 2, '槓鈴划船', 4, 10),
  ('PPL - Pull (拉)', 3, '坐姿划船', 3, 12),
  ('PPL - Pull (拉)', 4, '槓鈴彎舉', 3, 10),
  ('PPL - Legs (腿)', 0, '深蹲', 4, 8),
  ('PPL - Legs (腿)', 1, '羅馬尼亞硬舉', 4, 10),
  ('PPL - Legs (腿)', 2, '腿推機', 4, 12),
  ('PPL - Legs (腿)', 3, '腿彎舉', 3, 12),
  ('PPL - Legs (腿)', 4, '提踵', 4, 15),
  ('上肢訓練', 0, '槓鈴臥推', 4, 8),
  ('上肢訓練', 1, '槓鈴划船', 4, 10),
  ('上肢訓練', 2, '肩推', 3, 10),
  ('上肢訓練', 3, '槓鈴彎舉', 3, 12),
  ('上肢訓練', 4, '三頭下壓', 3, 12),
  ('全身訓練', 0, '深蹲', 3, 10),
  ('全身訓練', 1, '槓鈴臥推', 3, 10),
  ('全身訓練', 2, '硬舉', 3, 8),
  ('全身訓練', 3, '引體向上', 3, 8),
  ('全身訓練', 4, '肩推', 3, 10)
) as v(template_name, order_index, exercise_name, suggested_sets, suggested_reps)
on conflict (id) do nothing;
