// OfflineCachedUserRepository / OfflineCachedExerciseRepository:雲端成功時
// 快取到本機(key = auth uid),網路失敗時回快取;不同 uid 互不可見。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart' as db;
import 'package:workout_record/data/models/exercise.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/offline/offline_cached_exercise_repository.dart';
import 'package:workout_record/data/repositories/offline/offline_cached_user_repository.dart';
import 'package:workout_record/data/repositories/user_repository.dart';

import 'fake_cloud_workout_repository.dart' show FakeOfflineException;

final _t0 = DateTime(2026, 11, 10, 9);

class _FakeCloudUsers implements UserRepository {
  final Map<String, db.User> rows = {};
  bool offline = false;
  String? Function() currentUid = () => null;
  int calls = 0;

  @override
  Future<db.User?> getById(String id) async {
    calls += 1;
    if (offline) throw const FakeOfflineException();
    // 同 SupabaseUserRepository:只看得到登入者本人。
    if (id != currentUid()) return null;
    return rows[id];
  }

  @override
  Future<bool> ensure(String id, {String? name, String? email}) async {
    calls += 1;
    if (offline) throw const FakeOfflineException();
    return false;
  }
}

class _FakeCloudExercises implements ExerciseRepository {
  List<Exercise> all = [];
  bool offline = false;
  final List<String> calls = [];

  void _enter(String name) {
    calls.add(name);
    if (offline) throw const FakeOfflineException();
  }

  @override
  Future<List<Exercise>> fetchAll({bool includeInactive = false}) async {
    _enter('fetchAll');
    return [
      for (final e in all)
        if (includeInactive || e.isActive) e,
    ];
  }

  @override
  Future<List<Exercise>> fetchByCategory(String categoryId) async {
    _enter('fetchByCategory');
    return [
      for (final e in all)
        if (e.isActive && e.categoryId == categoryId) e,
    ];
  }

  @override
  Future<void> create(Exercise exercise) async {
    _enter('create');
    all = [...all, exercise];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

db.User _user(String id, String name) => db.User(
  id: id,
  name: name,
  email: '$name@example.com',
  createdAt: _t0,
  updatedAt: _t0,
);

Exercise _ex(
  String id,
  String name,
  String category, {
  bool active = true,
  String? userId,
}) => Exercise(
  id: id,
  name: name,
  categoryId: category,
  type: ExerciseType.values.first,
  isSystem: userId == null,
  isActive: active,
  userId: userId,
  createdAt: _t0,
  updatedAt: _t0,
);

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('OfflineCachedUserRepository', () {
    late _FakeCloudUsers cloud;
    String? uid;
    late OfflineCachedUserRepository repo;

    setUp(() {
      uid = 'uid-a';
      cloud = _FakeCloudUsers()..currentUid = () => uid;
      cloud.rows['uid-a'] = _user('uid-a', 'alice');
      cloud.rows['uid-b'] = _user('uid-b', 'bob');
      repo = OfflineCachedUserRepository(cloud, prefs, () => uid);
    });

    test('雲端成功 → 快取;離線 → 回快取(重建 repository 後仍有效)', () async {
      expect((await repo.getById('uid-a'))!.name, 'alice');
      cloud.offline = true;

      final restarted = OfflineCachedUserRepository(cloud, prefs, () => uid);
      final cached = await restarted.getById('uid-a');
      expect(cached!.id, 'uid-a');
      expect(cached.name, 'alice');
      expect(cached.email, 'alice@example.com');
      expect(cached.createdAt, _t0);
    });

    test('離線且沒有快取 → 拋原錯誤', () async {
      cloud.offline = true;
      expect(() => repo.getById('uid-a'), throwsA(isA<FakeOfflineException>()));
    });

    test('不得把 A 的快取交給 B:換帳號後離線查 B → 拋錯;查 A 的 id → 也拋錯', () async {
      await repo.getById('uid-a');
      uid = 'uid-b';
      cloud.offline = true;
      await expectLater(
        repo.getById('uid-b'),
        throwsA(isA<FakeOfflineException>()),
      );
      await expectLater(
        repo.getById('uid-a'),
        throwsA(isA<FakeOfflineException>()),
      );
    });

    test('查詢 id 不是目前登入者 → 不寫快取', () async {
      await repo.getById('uid-b');
      expect(
        prefs.getKeys().where(
          (k) => k.startsWith(OfflineCachedUserRepository.keyPrefix),
        ),
        isEmpty,
      );
    });

    test('雲端明確回 null(列不存在)→ 清掉快取', () async {
      await repo.getById('uid-a');
      cloud.rows.remove('uid-a');
      expect(await repo.getById('uid-a'), isNull);
      cloud.offline = true;
      expect(() => repo.getById('uid-a'), throwsA(isA<FakeOfflineException>()));
    });

    test('Error(非 Exception)不攔:照原樣拋出', () async {
      final throwing = OfflineCachedUserRepository(
        _ErrorUsers(),
        prefs,
        () => 'uid-a',
      );
      expect(() => throwing.getById('uid-a'), throwsStateError);
    });
  });

  group('OfflineCachedExerciseRepository', () {
    late _FakeCloudExercises cloud;
    String? uid;
    late OfflineCachedExerciseRepository repo;

    setUp(() {
      uid = 'uid-a';
      cloud = _FakeCloudExercises()
        ..all = [
          _ex('e1', 'Bench', 'chest'),
          _ex('e2', 'Squat', 'legs'),
          _ex('e3', 'Fly', 'chest'),
          _ex('e4', 'Old', 'chest', active: false),
          _ex('e5', 'My Curl', 'arms', userId: 'uid-a'),
        ];
      repo = OfflineCachedExerciseRepository(cloud, prefs, () => uid);
    });

    test('fetchAll 成功 → 快取;離線 → 回快取(重建後仍有效、欄位完整)', () async {
      final online = await repo.fetchAll();
      cloud.offline = true;

      final restarted = OfflineCachedExerciseRepository(
        cloud,
        prefs,
        () => uid,
      );
      final offline = await restarted.fetchAll();
      expect(offline.map((e) => e.id), online.map((e) => e.id));
      final curl = offline.firstWhere((e) => e.id == 'e5');
      expect(curl.name, 'My Curl');
      expect(curl.userId, 'uid-a');
      expect(curl.isSystem, isFalse);
      expect(curl.type, ExerciseType.values.first);
    });

    test('includeInactive 分開快取', () async {
      await repo.fetchAll();
      cloud.offline = true;
      expect(
        () => repo.fetchAll(includeInactive: true),
        throwsA(isA<FakeOfflineException>()),
      );
    });

    test('fetchByCategory 離線 → 由 active 快取篩出,不含停用動作', () async {
      await repo.fetchAll();
      cloud.offline = true;
      final chest = await repo.fetchByCategory('chest');
      expect(chest.map((e) => e.id), ['e1', 'e3']);
    });

    test('快取以 uid 區隔:換帳號後離線拿不到上一個帳號的清單', () async {
      await repo.fetchAll();
      uid = 'uid-b';
      cloud.offline = true;
      await expectLater(repo.fetchAll(), throwsA(isA<FakeOfflineException>()));
      await expectLater(
        repo.fetchByCategory('chest'),
        throwsA(isA<FakeOfflineException>()),
      );
    });

    test('新增自訂動作離線 → 照舊失敗(不排隊)', () async {
      cloud.offline = true;
      expect(
        () => repo.create(_ex('e9', 'New', 'arms', userId: 'uid-a')),
        throwsA(isA<FakeOfflineException>()),
      );
    });
  });
}

class _ErrorUsers implements UserRepository {
  @override
  Future<db.User?> getById(String id) async => throw StateError('未登入');

  @override
  Future<bool> ensure(String id, {String? name, String? email}) async => false;
}
