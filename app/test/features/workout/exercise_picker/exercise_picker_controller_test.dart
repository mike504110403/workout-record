// ExercisePickerController seam:直接透過 ProviderContainer 呼叫 controller
// 方法(不經 widget 樹),用來精準控制非同步時序(競態測試需要「A 比 B 晚
// 回來」這種時間點才做得到的斷言,widget test 的 tap+pumpAndSettle 沒辦法
// 可靠模擬)與 FK 血緣情境(userId 解析對照 dashboard_controller.dart
// `_resolveUserId` + onboarding_controller.dart `_ensureUserRow` 的慣例)。
//
// code review 打回項目:
// - major 1:selectCategory 競態(快速連點 A→B,A 較晚回來不能蓋掉 B)+
//   失敗路徑(fetchByCategory 拋錯不能變成 unhandled async error)。
// - major 3(優先):自訂動作 userId 解析要走「session id 查證存在」+
//   「查無此人退回血緣 key」的慣例,不能直接假設 session id 就是 Users
//   表裡的 id——血緣情境下直接塞會撞 FK。
//
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// code review r2 minor S4:改成 import 行級 ignore,不用 ignore_for_file——
// `depend_on_referenced_packages` 只跟這一行 import 有關,`ignore_for_file`
// 範圍是整個檔案,會連帶蓋掉檔案裡其他地方未來新增的、其實該被這條規則抓到
// 的違規 import。`shared_preferences_platform_interface` 是
// `shared_preferences` 的 transitive dependency(已存在 pubspec.lock,版本
// 不受這個 import 影響),要真的注入 SharedPreferences 寫入失敗(minor 1
// 測試),只能從這一層換掉底層 store——`SharedPreferences` 類別本身建構子是
// private,測試沒辦法直接 subclass/mock 它。brief 範圍禁止改依賴(不升
// 版本),這裡選擇 ignore 這條 info 等級的 lint,而不是去 pubspec.yaml 補
// 一行 direct dependency 宣告。
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:workout_record/data/db/app_database.dart' hide Exercise;
import 'package:workout_record/data/db/seed_data.dart';
import 'package:workout_record/data/migration/coredata_importer_result.dart';
import 'package:workout_record/data/models/exercise.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/workout/exercise_picker/exercise_picker_controller.dart';

import '../../../data/test_helpers.dart';

/// `fetchByCategory` 可用外部 [Completer] 控制何時回傳——用來製造「使用者
/// 快速連點兩個分類、較早點的那個查詢反而較晚回來」的競態情境。沒有掛
/// gate 的 categoryId 照常直接返回(真實查詢),不影響其他測試路徑。
class _GatedCategoryExerciseRepository extends ExerciseRepository {
  _GatedCategoryExerciseRepository(super.db);

  final Map<String, Completer<void>> gates = {};

  @override
  Future<List<Exercise>> fetchByCategory(String categoryId) async {
    final gate = gates[categoryId];
    if (gate != null) await gate.future;
    return super.fetchByCategory(categoryId);
  }
}

class _ThrowingFetchByCategoryRepository extends ExerciseRepository {
  _ThrowingFetchByCategoryRepository(super.db);

  @override
  Future<List<Exercise>> fetchByCategory(String categoryId) async {
    throw Exception('模擬分類查詢失敗(major 1 失敗路徑測試用)');
  }
}

/// 讓 `SharedPreferences.setStringList` 真的失敗的假後端(minor 1 測試
/// 用)——`SharedPreferences` 類別本身建構子是 private(`SharedPreferences._`),
/// 沒辦法直接 subclass/mock,但它底層寫入都會轉呼叫可替換的
/// [SharedPreferencesStorePlatform.instance],所以改從這一層注入失敗:
/// 繼承套件內建的記憶體實作 [InMemorySharedPreferencesStore],只把
/// `setValue`(所有 `set*` 系列方法的共同底層)覆寫成拋錯,`getAll`/初始資料
/// 讀取等其他行為完全沿用真正的記憶體實作。
class _ThrowingSetValueStore extends InMemorySharedPreferencesStore {
  _ThrowingSetValueStore.withData(super.data) : super.withData();

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    throw Exception('模擬 SharedPreferences 寫入失敗(minor 1 測試用)');
  }
}

/// `setValue` 回傳 `false`(寫入邏輯上失敗,但不拋例外)的假後端——
/// `toggleFavorite` 的還原邏輯有兩條路:`catch` 接住拋出的例外,以及
/// `if (!success)` 接住「沒拋錯但回傳失敗」這種情況(code review r2 minor
/// S6,原本只有拋例外那條路有測試)。真實資料不寫進底層(`_data` 不更新),
/// 對照真的寫入失敗但平台沒有丟例外的情境(例如某些平台實作用回傳值表達
/// 失敗,不是例外)。
class _FalseReturningSetValueStore extends InMemorySharedPreferencesStore {
  _FalseReturningSetValueStore.withData(super.data) : super.withData();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async => false;
}

typedef _Harness = ({AppDatabase db, ProviderContainer container});

Future<_Harness> _setUpHarness({
  Map<String, Object> prefs = const {},
  ExerciseRepository Function(AppDatabase db)? exerciseRepoBuilder,
  bool seedUser = true,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final resolvedPrefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  if (seedUser) {
    await seedTestUser(db);
  }
  final exerciseRepo = exerciseRepoBuilder?.call(db) ?? ExerciseRepository(db);

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(resolvedPrefs),
      appDatabaseProvider.overrideWithValue(db),
      exerciseRepositoryProvider.overrideWithValue(exerciseRepo),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  return (db: db, container: container);
}

void main() {
  group('selectCategory 競態與失敗路徑(major 1)', () {
    test('快速連點背部(A)→腿部(B),A 較晚回來時不能蓋掉 B 的結果', () async {
      SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
      final prefs = await SharedPreferences.getInstance();
      final db = openTestDatabase();
      await seedTestUser(db);
      addTearDown(db.close);

      final repo = _GatedCategoryExerciseRepository(db);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
          exerciseRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(exercisePickerControllerProvider.future);
      final notifier = container.read(exercisePickerControllerProvider.notifier);

      final gateBack = Completer<void>();
      final gateLegs = Completer<void>();
      repo.gates[SeedCategoryIds.back] = gateBack;
      repo.gates[SeedCategoryIds.legs] = gateLegs;

      // 使用者先點背部(A),還沒回來就改點腿部(B)。
      final futureA = notifier.selectCategory(SeedCategoryIds.back);
      final futureB = notifier.selectCategory(SeedCategoryIds.legs);

      // B 先回來、A(較早點的)較晚回來——模擬使用者快速切換時常見的
      // 「先送出的請求反而後回應」。
      gateLegs.complete();
      await futureB;
      gateBack.complete();
      await futureA;

      final state = container.read(exercisePickerControllerProvider).value!;
      expect(state.selectedCategoryId, SeedCategoryIds.legs);
      expect(state.categoryExercises, isNotEmpty);
      expect(state.categoryExercises.every((e) => e.categoryId == SeedCategoryIds.legs), isTrue);
      // A 的結果沒有偷偷蓋掉 B:不該出現只在背部分類的動作。
      expect(state.categoryExercises.any((e) => e.name == '槓鈴划船'), isFalse);
    });

    test('fetchByCategory 拋錯不會變成 unhandled async error,錯誤寫進 state.categoryError', () async {
      final harness = await _setUpHarness(
        prefs: {kAppleUserIdKey: testUserId},
        exerciseRepoBuilder: (db) => _ThrowingFetchByCategoryRepository(db),
      );
      await harness.container.read(exercisePickerControllerProvider.future);
      final notifier = harness.container.read(exercisePickerControllerProvider.notifier);

      // 關鍵斷言本身就是「這個 await 沒有拋出例外」——selectCategory 內部
      // try/catch 沒接住的話,這行就會讓測試直接失敗(unhandled exception)。
      await notifier.selectCategory(SeedCategoryIds.back);

      final state = harness.container.read(exercisePickerControllerProvider).value!;
      expect(state.categoryError, isNotNull);
      // 失敗時不假裝切換成功:selectedCategoryId 維持切換前的狀態(null)。
      expect(state.selectedCategoryId, isNull);
    });

    test('查詢成功後 categoryError 清成 null(先前的失敗不會殘留提示)', () async {
      final harness = await _setUpHarness(prefs: {kAppleUserIdKey: testUserId});
      await harness.container.read(exercisePickerControllerProvider.future);
      final notifier = harness.container.read(exercisePickerControllerProvider.notifier);

      await notifier.selectCategory(SeedCategoryIds.back);
      final state = harness.container.read(exercisePickerControllerProvider).value!;
      expect(state.categoryError, isNull);
      expect(state.selectedCategoryId, SeedCategoryIds.back);
    });
  });

  group('自訂動作 userId 解析(major 3,優先)', () {
    test(
      '血緣情境:session 登入 id 在 Users 表查無此人,退回 coredata_imported_user_id '
      '對應的既有 row,新增自訂動作成功且 userId 指向那筆真實 row(不是登入 id)',
      () async {
        const loginUserId = 'new-login-id-not-in-users-table';
        const legacyUserId = 'legacy-user-from-coredata-import';

        SharedPreferences.setMockInitialValues({
          kAppleUserIdKey: loginUserId,
          kCoreDataImportedUserIdKey: legacyUserId,
        });
        final prefs = await SharedPreferences.getInstance();
        final db = openTestDatabase();
        addTearDown(db.close);
        // 只建血緣那筆 Users row,刻意不建登入 id 那筆——重現「換了登入方式
        // /裝置,session id 與 Users 表既有 row id 不同」的情境。
        await seedTestUser(db, id: legacyUserId);

        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            appDatabaseProvider.overrideWithValue(db),
          ],
        );
        addTearDown(container.dispose);

        await container.read(exercisePickerControllerProvider.future);
        final notifier = container.read(exercisePickerControllerProvider.notifier);

        final created = await notifier.addCustomExercise(
          name: '血緣情境自訂動作',
          categoryId: SeedCategoryIds.chest,
          type: ExerciseType.freeWeight,
        );

        // 這是這條測試存在的意義:若實作誤用登入 id(loginUserId)當
        // userId,`ExerciseRepository.create` 的 insert 會因為 FK 參照不到
        // 對應 Users row 而拋錯,`addCustomExercise` 的 catch 分支會把它
        // 轉成 null 回傳——`created` 非 null 本身就是「沒有撞 FK」的證據。
        expect(created, isNotNull);
        expect(created!.userId, legacyUserId);
        expect(created.userId, isNot(loginUserId));

        final rows = await (db.select(
          db.exercises,
        )..where((t) => t.name.equals('血緣情境自訂動作'))).get();
        expect(rows, hasLength(1));
        expect(rows.single.userId, legacyUserId);

        final state = container.read(exercisePickerControllerProvider).value!;
        expect(state.customExerciseError, isNull);
      },
    );

    test('登入 id 與血緣 id 都查無對應 Users row 時,userId 落 null(nullable FK,新增仍成功)', () async {
      final harness = await _setUpHarness(
        prefs: {kAppleUserIdKey: 'ghost-id-not-in-users-table'},
        seedUser: false,
      );
      await harness.container.read(exercisePickerControllerProvider.future);
      final notifier = harness.container.read(exercisePickerControllerProvider.notifier);

      final created = await notifier.addCustomExercise(
        name: '無主自訂動作',
        categoryId: SeedCategoryIds.chest,
        type: ExerciseType.freeWeight,
      );

      expect(created, isNotNull);
      expect(created!.userId, isNull);

      final rows = await (harness.db.select(
        harness.db.exercises,
      )..where((t) => t.name.equals('無主自訂動作'))).get();
      expect(rows.single.userId, isNull);
    });

    test('session 登入 id 本身就是既有 Users row 時(一般情境),優先採用它,不需要退回血緣 key', () async {
      final harness = await _setUpHarness(prefs: {kAppleUserIdKey: testUserId});
      await harness.container.read(exercisePickerControllerProvider.future);
      final notifier = harness.container.read(exercisePickerControllerProvider.notifier);

      final created = await notifier.addCustomExercise(
        name: '一般情境自訂動作',
        categoryId: SeedCategoryIds.chest,
        type: ExerciseType.freeWeight,
      );

      expect(created!.userId, testUserId);
    });
  });

  group('toggleFavorite 失敗還原(minor 1)', () {
    test('SharedPreferences 寫入真的拋錯時,favoriteIds 還原成切換前的狀態(不留在樂觀更新的錯誤畫面)', () async {
      // `SharedPreferences.getInstance()` 內部把已解析的實例快取在一個靜態
      // `Completer`(見 shared_preferences_legacy.dart)——若前一條測試已經
      // 呼叫過 `getInstance()`,這裡直接呼叫會撈到「前一條測試的快取結果」,
      // 不會真的用我們接下來設定的假 store 重建。`setMockInitialValues({})`
      // 是套件公開、唯一會重置這個快取(`_completer = null`)的入口,先呼叫
      // 它清快取,再把底層 store 換成會拋錯的版本,`getInstance()` 才會照
      // 我們要的假 store 建立新實例。
      //
      // `SharedPreferences` legacy API 內部一律把 key 加上 `flutter.` 前綴
      // 才存進底層 store,初始資料要照這個慣例塞,`getString` 之類的讀取
      // 才找得到。
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = _ThrowingSetValueStore.withData({
        'flutter.$kAppleUserIdKey': testUserId,
      });
      // 這條測試結束後把靜態的 platform store/快取都還原成乾淨狀態,不讓
      // 這個會拋錯的假 store 污染同一個測試進程裡跑在它之後的其他測試。
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      final throwingPrefs = await SharedPreferences.getInstance();

      final db = openTestDatabase();
      addTearDown(db.close);
      await seedTestUser(db);

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(throwingPrefs),
          appDatabaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      await container.read(exercisePickerControllerProvider.future);
      final notifier = container.read(exercisePickerControllerProvider.notifier);

      final before = container.read(exercisePickerControllerProvider).value!;
      final targetId = before.allExercises.first.id;
      expect(before.favoriteIds.contains(targetId), isFalse);

      // 關鍵斷言之一:這個 await 本身不能拋出例外——toggleFavorite 的
      // try/catch 必須把 setStringList 的失敗吃下來,不能讓它變成
      // unhandled async error 炸穿呼叫端。
      await notifier.toggleFavorite(targetId);

      final after = container.read(exercisePickerControllerProvider).value!;
      // 樂觀更新的 favoriteIds 已經還原回失敗前的狀態,畫面不會停在
      // 「看起來已收藏、實際上沒寫進去」的不一致狀態。
      expect(after.favoriteIds.contains(targetId), isFalse);
      expect(after.favoriteIds, before.favoriteIds);
    });

    test(
      'SharedPreferences 寫入回傳 false(不拋錯)時,favoriteIds 一樣還原成切換前的狀態'
      '(code review r2 minor S6:拋例外與回傳 false 是 toggleFavorite 兩條不同的還原分支)',
      () async {
        SharedPreferences.setMockInitialValues({});
        SharedPreferencesStorePlatform.instance = _FalseReturningSetValueStore.withData({
          'flutter.$kAppleUserIdKey': testUserId,
        });
        addTearDown(() => SharedPreferences.setMockInitialValues({}));
        final falseReturningPrefs = await SharedPreferences.getInstance();

        final db = openTestDatabase();
        addTearDown(db.close);
        await seedTestUser(db);

        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(falseReturningPrefs),
            appDatabaseProvider.overrideWithValue(db),
          ],
        );
        addTearDown(container.dispose);

        await container.read(exercisePickerControllerProvider.future);
        final notifier = container.read(exercisePickerControllerProvider.notifier);

        final before = container.read(exercisePickerControllerProvider).value!;
        final targetId = before.allExercises.first.id;
        expect(before.favoriteIds.contains(targetId), isFalse);

        await notifier.toggleFavorite(targetId);

        final after = container.read(exercisePickerControllerProvider).value!;
        expect(after.favoriteIds.contains(targetId), isFalse);
        expect(after.favoriteIds, before.favoriteIds);
      },
    );
  });
}
