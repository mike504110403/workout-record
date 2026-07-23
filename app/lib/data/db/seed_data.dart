// 內建動作庫(system exercises)種子資料。
//
// ## 資料來源
// 逐筆對照 ios/WorkoutRecord/WorkoutRecord/Sources/Data/MockData.swift 的
// `chestExercises` / `backExercises` / `legExercises` / `shoulderExercises` /
// `armExercises` / `coreExercises`(合計即 `allExercises`,共 66 筆),
// 並與 app/test/fixtures/WorkoutRecord.sqlite 的 ZEXERCISEENTITY 66 筆
// (ZISSYSTEM = 1)互相驗證一致,確認 66 筆即完整內建清單。
//
// 名稱刻意保留 2 組跨分類重複(對照 MockData.swift 原始寫法):
// 「硬舉」同時存在於背部(pull)與腿部(hinge)分類、
// 「臉拉」同時存在於背部與肩部分類 —— 這是原始設計,不是資料錯誤,故本檔案照抄。
//
// ## UUID 策略判斷:id 不用固定值,採「名稱」當穩定鍵
// 依據:
// 1. ios/.../Sources/Models/Exercise.swift 第 118~120 行:
//    `init(id: UUID = UUID(), name: String, ...)` —— id 有預設值,呼叫端不傳就隨機產生。
// 2. ios/.../Sources/Data/MockData.swift 裡所有 `Exercise(name: ..., ...)` 呼叫
//    (見 chestExercises 等 6 個陣列)都「沒有」傳入 id 參數。
// 3. 因此 ios/.../Sources/Services/DataMigrationService.swift 的
//    `initializeSystemExercises()` 在每次全新安裝時,66 筆系統動作的 id
//    都是當下才隨機產生的 UUID v4 —— 不同裝置、不同安裝之間的系統動作 id 並不相同。
//    (可用 app/test/fixtures/WorkoutRecord.sqlite 佐證:hex(ZID) 是隨機 V4 UUID,
//     並非任何規律值。)
//
// 結論:Flutter 版 seed 不能依賴 fixture 裡的固定 UUID 做跨裝置/跨版本比對,
// 系統動作的穩定鍵改用「名稱(name)」;id 在插入當下用 [generateUuidV4] 自行產生。
//
// 唯一的例外是 categoryId:MockData.swift 第 8~15 行的 `categories` 陣列
// 明確用寫死的 UUID(00000000-0000-0000-0000-000000000001~6,依序對應
// 胸部/背部/腿部/肩部/手臂/核心,並在陣列開頭註明「使用固定的 UUID,確保
// 每次啟動 App 時分類 ID 保持一致」),所以 categoryId 這裡直接複用同一組常數。

import 'dart:math';

import 'package:drift/drift.dart';

import 'app_database.dart';

/// 對照 MockData.swift 的 `categories` 陣列(寫死的固定 UUID,見檔案開頭說明)。
class SeedCategoryIds {
  static const chest = '00000000-0000-0000-0000-000000000001';
  static const back = '00000000-0000-0000-0000-000000000002';
  static const legs = '00000000-0000-0000-0000-000000000003';
  static const shoulders = '00000000-0000-0000-0000-000000000004';
  static const arms = '00000000-0000-0000-0000-000000000005';
  static const core = '00000000-0000-0000-0000-000000000006';
}

/// 單筆內建動作的種子定義(id 不在此列 —— 插入當下才產生,見檔案開頭說明)。
class SeedExercise {
  final String name;
  final String? nameEn;
  final String categoryId;
  final String type;
  final String? movementPattern;
  final String? primaryMuscleGroup;

  const SeedExercise({
    required this.name,
    this.nameEn,
    required this.categoryId,
    required this.type,
    this.movementPattern,
    this.primaryMuscleGroup,
  });
}

/// 66 筆內建動作,依 MockData.swift 的 6 個分類分組排列。
const List<SeedExercise> kSeedExercises = [
  // 胸部 Chest (12)
  SeedExercise(name: '槓鈴臥推', nameEn: 'Barbell Bench Press', categoryId: SeedCategoryIds.chest, type: 'free_weight', movementPattern: 'push', primaryMuscleGroup: 'chest'),
  SeedExercise(name: '啞鈴臥推', nameEn: 'Dumbbell Bench Press', categoryId: SeedCategoryIds.chest, type: 'free_weight', movementPattern: 'push', primaryMuscleGroup: 'chest'),
  SeedExercise(name: '上斜槓鈴臥推', nameEn: 'Incline Barbell Press', categoryId: SeedCategoryIds.chest, type: 'free_weight', movementPattern: 'push', primaryMuscleGroup: 'chest'),
  SeedExercise(name: '上斜啞鈴臥推', nameEn: 'Incline Dumbbell Press', categoryId: SeedCategoryIds.chest, type: 'free_weight', movementPattern: 'push', primaryMuscleGroup: 'chest'),
  SeedExercise(name: '下斜槓鈴臥推', nameEn: 'Decline Barbell Press', categoryId: SeedCategoryIds.chest, type: 'free_weight', movementPattern: 'push', primaryMuscleGroup: 'chest'),
  SeedExercise(name: '啞鈴飛鳥', nameEn: 'Dumbbell Fly', categoryId: SeedCategoryIds.chest, type: 'free_weight', movementPattern: 'isolation', primaryMuscleGroup: 'chest'),
  SeedExercise(name: '上斜啞鈴飛鳥', nameEn: 'Incline Dumbbell Fly', categoryId: SeedCategoryIds.chest, type: 'free_weight', movementPattern: 'isolation', primaryMuscleGroup: 'chest'),
  SeedExercise(name: '胸推機', nameEn: 'Chest Press Machine', categoryId: SeedCategoryIds.chest, type: 'machine', movementPattern: 'push', primaryMuscleGroup: 'chest'),
  SeedExercise(name: '蝴蝶機', nameEn: 'Pec Deck Fly', categoryId: SeedCategoryIds.chest, type: 'machine', movementPattern: 'isolation', primaryMuscleGroup: 'chest'),
  SeedExercise(name: 'Cable 飛鳥', nameEn: 'Cable Crossover', categoryId: SeedCategoryIds.chest, type: 'machine', movementPattern: 'isolation', primaryMuscleGroup: 'chest'),
  SeedExercise(name: '伏地挺身', nameEn: 'Push-up', categoryId: SeedCategoryIds.chest, type: 'bodyweight', movementPattern: 'push', primaryMuscleGroup: 'chest'),
  SeedExercise(name: '雙槓撐體', nameEn: 'Dips', categoryId: SeedCategoryIds.chest, type: 'bodyweight', movementPattern: 'push', primaryMuscleGroup: 'chest'),

  // 背部 Back (11) —— 「硬舉」「臉拉」為刻意跨分類重複,見檔案開頭說明
  SeedExercise(name: '硬舉', nameEn: 'Deadlift', categoryId: SeedCategoryIds.back, type: 'free_weight', movementPattern: 'pull', primaryMuscleGroup: 'back'),
  SeedExercise(name: '槓鈴划船', nameEn: 'Barbell Row', categoryId: SeedCategoryIds.back, type: 'free_weight', movementPattern: 'pull', primaryMuscleGroup: 'back'),
  SeedExercise(name: '啞鈴划船', nameEn: 'Dumbbell Row', categoryId: SeedCategoryIds.back, type: 'free_weight', movementPattern: 'pull', primaryMuscleGroup: 'back'),
  SeedExercise(name: 'T 槓划船', nameEn: 'T-Bar Row', categoryId: SeedCategoryIds.back, type: 'free_weight', movementPattern: 'pull', primaryMuscleGroup: 'back'),
  SeedExercise(name: '引體向上', nameEn: 'Pull-up', categoryId: SeedCategoryIds.back, type: 'bodyweight', movementPattern: 'pull', primaryMuscleGroup: 'back'),
  SeedExercise(name: '滑輪下拉', nameEn: 'Lat Pulldown', categoryId: SeedCategoryIds.back, type: 'machine', movementPattern: 'pull', primaryMuscleGroup: 'back'),
  SeedExercise(name: '坐姿划船', nameEn: 'Seated Cable Row', categoryId: SeedCategoryIds.back, type: 'machine', movementPattern: 'pull', primaryMuscleGroup: 'back'),
  SeedExercise(name: '單臂啞鈴划船', nameEn: 'One-Arm Dumbbell Row', categoryId: SeedCategoryIds.back, type: 'free_weight', movementPattern: 'pull', primaryMuscleGroup: 'back'),
  SeedExercise(name: '直臂下壓', nameEn: 'Straight Arm Pulldown', categoryId: SeedCategoryIds.back, type: 'machine', movementPattern: 'isolation', primaryMuscleGroup: 'back'),
  SeedExercise(name: '臉拉', nameEn: 'Face Pull', categoryId: SeedCategoryIds.back, type: 'machine', movementPattern: 'pull', primaryMuscleGroup: 'shoulders'),
  SeedExercise(name: '反向飛鳥', nameEn: 'Reverse Fly', categoryId: SeedCategoryIds.back, type: 'free_weight', movementPattern: 'isolation', primaryMuscleGroup: 'shoulders'),

  // 腿部 Legs (12)
  SeedExercise(name: '深蹲', nameEn: 'Squat', categoryId: SeedCategoryIds.legs, type: 'free_weight', movementPattern: 'squat', primaryMuscleGroup: 'legs'),
  SeedExercise(name: '前蹲', nameEn: 'Front Squat', categoryId: SeedCategoryIds.legs, type: 'free_weight', movementPattern: 'squat', primaryMuscleGroup: 'legs'),
  SeedExercise(name: '硬舉', nameEn: 'Deadlift', categoryId: SeedCategoryIds.legs, type: 'free_weight', movementPattern: 'hinge', primaryMuscleGroup: 'legs'),
  SeedExercise(name: '羅馬尼亞硬舉', nameEn: 'Romanian Deadlift', categoryId: SeedCategoryIds.legs, type: 'free_weight', movementPattern: 'hinge', primaryMuscleGroup: 'legs'),
  SeedExercise(name: '腿推機', nameEn: 'Leg Press', categoryId: SeedCategoryIds.legs, type: 'machine', movementPattern: 'squat', primaryMuscleGroup: 'legs'),
  SeedExercise(name: '腿伸屈', nameEn: 'Leg Extension', categoryId: SeedCategoryIds.legs, type: 'machine', movementPattern: 'isolation', primaryMuscleGroup: 'legs'),
  SeedExercise(name: '腿彎舉', nameEn: 'Leg Curl', categoryId: SeedCategoryIds.legs, type: 'machine', movementPattern: 'isolation', primaryMuscleGroup: 'legs'),
  SeedExercise(name: '保加利亞分腿蹲', nameEn: 'Bulgarian Split Squat', categoryId: SeedCategoryIds.legs, type: 'free_weight', movementPattern: 'squat', primaryMuscleGroup: 'legs'),
  SeedExercise(name: '箭步蹲', nameEn: 'Lunge', categoryId: SeedCategoryIds.legs, type: 'free_weight', movementPattern: 'squat', primaryMuscleGroup: 'legs'),
  SeedExercise(name: '臀推', nameEn: 'Hip Thrust', categoryId: SeedCategoryIds.legs, type: 'free_weight', movementPattern: 'hinge', primaryMuscleGroup: 'legs'),
  SeedExercise(name: '提踵', nameEn: 'Calf Raise', categoryId: SeedCategoryIds.legs, type: 'free_weight', movementPattern: 'isolation', primaryMuscleGroup: 'legs'),
  SeedExercise(name: '坐姿提踵', nameEn: 'Seated Calf Raise', categoryId: SeedCategoryIds.legs, type: 'machine', movementPattern: 'isolation', primaryMuscleGroup: 'legs'),

  // 肩部 Shoulders (10)
  SeedExercise(name: '肩推', nameEn: 'Overhead Press', categoryId: SeedCategoryIds.shoulders, type: 'free_weight', movementPattern: 'push', primaryMuscleGroup: 'shoulders'),
  SeedExercise(name: '啞鈴肩推', nameEn: 'Dumbbell Shoulder Press', categoryId: SeedCategoryIds.shoulders, type: 'free_weight', movementPattern: 'push', primaryMuscleGroup: 'shoulders'),
  SeedExercise(name: '阿諾推舉', nameEn: 'Arnold Press', categoryId: SeedCategoryIds.shoulders, type: 'free_weight', movementPattern: 'push', primaryMuscleGroup: 'shoulders'),
  SeedExercise(name: '側平舉', nameEn: 'Lateral Raise', categoryId: SeedCategoryIds.shoulders, type: 'free_weight', movementPattern: 'isolation', primaryMuscleGroup: 'shoulders'),
  SeedExercise(name: '前平舉', nameEn: 'Front Raise', categoryId: SeedCategoryIds.shoulders, type: 'free_weight', movementPattern: 'isolation', primaryMuscleGroup: 'shoulders'),
  SeedExercise(name: '俯身側平舉', nameEn: 'Bent-Over Lateral Raise', categoryId: SeedCategoryIds.shoulders, type: 'free_weight', movementPattern: 'isolation', primaryMuscleGroup: 'shoulders'),
  SeedExercise(name: '直立划船', nameEn: 'Upright Row', categoryId: SeedCategoryIds.shoulders, type: 'free_weight', movementPattern: 'pull', primaryMuscleGroup: 'shoulders'),
  SeedExercise(name: '肩推機', nameEn: 'Shoulder Press Machine', categoryId: SeedCategoryIds.shoulders, type: 'machine', movementPattern: 'push', primaryMuscleGroup: 'shoulders'),
  SeedExercise(name: 'Cable 側平舉', nameEn: 'Cable Lateral Raise', categoryId: SeedCategoryIds.shoulders, type: 'machine', movementPattern: 'isolation', primaryMuscleGroup: 'shoulders'),
  SeedExercise(name: '臉拉', nameEn: 'Face Pull', categoryId: SeedCategoryIds.shoulders, type: 'machine', movementPattern: 'pull', primaryMuscleGroup: 'shoulders'),

  // 手臂 Arms (11)
  SeedExercise(name: '槓鈴彎舉', nameEn: 'Barbell Curl', categoryId: SeedCategoryIds.arms, type: 'free_weight', movementPattern: 'pull', primaryMuscleGroup: 'arms'),
  SeedExercise(name: '啞鈴彎舉', nameEn: 'Dumbbell Curl', categoryId: SeedCategoryIds.arms, type: 'free_weight', movementPattern: 'pull', primaryMuscleGroup: 'arms'),
  SeedExercise(name: '錘式彎舉', nameEn: 'Hammer Curl', categoryId: SeedCategoryIds.arms, type: 'free_weight', movementPattern: 'pull', primaryMuscleGroup: 'arms'),
  SeedExercise(name: '集中彎舉', nameEn: 'Concentration Curl', categoryId: SeedCategoryIds.arms, type: 'free_weight', movementPattern: 'isolation', primaryMuscleGroup: 'arms'),
  SeedExercise(name: '三頭下壓', nameEn: 'Tricep Pushdown', categoryId: SeedCategoryIds.arms, type: 'machine', movementPattern: 'push', primaryMuscleGroup: 'arms'),
  SeedExercise(name: '過頭三頭伸展', nameEn: 'Overhead Tricep Extension', categoryId: SeedCategoryIds.arms, type: 'free_weight', movementPattern: 'isolation', primaryMuscleGroup: 'arms'),
  SeedExercise(name: '窄握臥推', nameEn: 'Close-Grip Bench Press', categoryId: SeedCategoryIds.arms, type: 'free_weight', movementPattern: 'push', primaryMuscleGroup: 'arms'),
  SeedExercise(name: '啞鈴三頭後踢', nameEn: 'Tricep Kickback', categoryId: SeedCategoryIds.arms, type: 'free_weight', movementPattern: 'isolation', primaryMuscleGroup: 'arms'),
  SeedExercise(name: 'Cable 彎舉', nameEn: 'Cable Curl', categoryId: SeedCategoryIds.arms, type: 'machine', movementPattern: 'pull', primaryMuscleGroup: 'arms'),
  SeedExercise(name: 'EZ Bar 彎舉', nameEn: 'EZ Bar Curl', categoryId: SeedCategoryIds.arms, type: 'free_weight', movementPattern: 'pull', primaryMuscleGroup: 'arms'),
  SeedExercise(name: '反握彎舉', nameEn: 'Reverse Curl', categoryId: SeedCategoryIds.arms, type: 'free_weight', movementPattern: 'pull', primaryMuscleGroup: 'arms'),

  // 核心 Core (10)
  SeedExercise(name: '捲腹', nameEn: 'Crunch', categoryId: SeedCategoryIds.core, type: 'bodyweight', movementPattern: 'isolation', primaryMuscleGroup: 'core'),
  SeedExercise(name: '仰臥起坐', nameEn: 'Sit-up', categoryId: SeedCategoryIds.core, type: 'bodyweight', movementPattern: 'isolation', primaryMuscleGroup: 'core'),
  SeedExercise(name: '棒式', nameEn: 'Plank', categoryId: SeedCategoryIds.core, type: 'bodyweight', movementPattern: 'isolation', primaryMuscleGroup: 'core'),
  SeedExercise(name: '側棒式', nameEn: 'Side Plank', categoryId: SeedCategoryIds.core, type: 'bodyweight', movementPattern: 'isolation', primaryMuscleGroup: 'core'),
  SeedExercise(name: '懸吊舉腿', nameEn: 'Hanging Leg Raise', categoryId: SeedCategoryIds.core, type: 'bodyweight', movementPattern: 'isolation', primaryMuscleGroup: 'core'),
  SeedExercise(name: '捲腹機', nameEn: 'Ab Crunch Machine', categoryId: SeedCategoryIds.core, type: 'machine', movementPattern: 'isolation', primaryMuscleGroup: 'core'),
  SeedExercise(name: 'Cable 捲腹', nameEn: 'Cable Crunch', categoryId: SeedCategoryIds.core, type: 'machine', movementPattern: 'isolation', primaryMuscleGroup: 'core'),
  SeedExercise(name: 'Russian Twist', nameEn: 'Russian Twist', categoryId: SeedCategoryIds.core, type: 'bodyweight', movementPattern: 'isolation', primaryMuscleGroup: 'core'),
  SeedExercise(name: '登山者式', nameEn: 'Mountain Climber', categoryId: SeedCategoryIds.core, type: 'bodyweight', movementPattern: 'isolation', primaryMuscleGroup: 'core'),
  SeedExercise(name: '腹輪', nameEn: 'Ab Wheel', categoryId: SeedCategoryIds.core, type: 'bodyweight', movementPattern: 'isolation', primaryMuscleGroup: 'core'),
];

/// 產生一組隨機 UUID v4 字串(標準 8-4-4-4-12 格式)。
///
/// 專案目前未加入 `uuid` package(見 app/pubspec.yaml),且本檔案改動範圍
/// 限定在 seed_data.dart / app_database.dart,因此不新增依賴,改用
/// `dart:math` 手刻,符合 RFC 4122 version 4 規則。
String generateUuidV4() {
  final rand = Random.secure();
  final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
  bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant 10xx
  String hex(int start, int end) => bytes
      .sublist(start, end)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// 將 [kSeedExercises] 轉成可插入 `Exercises` 表的 Companion 清單。
/// id 在此當下產生(見檔案開頭 UUID 策略說明);createdAt/updatedAt 統一
/// 用同一個時間戳,代表「這批系統動作是同時建立的」。
List<ExercisesCompanion> buildSeedExerciseCompanions() {
  final now = DateTime.now();
  return kSeedExercises
      .map(
        (seed) => ExercisesCompanion.insert(
          id: generateUuidV4(),
          name: seed.name,
          nameEn: Value(seed.nameEn),
          categoryId: seed.categoryId,
          type: seed.type,
          movementPattern: Value(seed.movementPattern),
          primaryMuscleGroup: Value(seed.primaryMuscleGroup),
          isSystem: const Value(true),
          isActive: const Value(true),
          createdAt: now,
          updatedAt: now,
        ),
      )
      .toList();
}
