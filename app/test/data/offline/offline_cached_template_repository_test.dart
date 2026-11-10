// OfflineCachedTemplateRepository:模板清單成功時依 uid 快取,網路失敗時回
// 快取(含巢狀動作與排序);fetchById 離線時從快取找;不同 uid 互不可見。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/models/exercise.dart';
import 'package:workout_record/data/models/workout_template.dart';
import 'package:workout_record/data/repositories/offline/offline_cached_template_repository.dart';
import 'package:workout_record/data/repositories/template_repository.dart';

import 'fake_cloud_workout_repository.dart' show FakeOfflineException;

final _t0 = DateTime.utc(2026, 11, 10, 9);

class _FakeCloudTemplates implements TemplateRepository {
  List<WorkoutTemplate> user = [];
  List<WorkoutTemplate> system = [];
  bool offline = false;
  final List<String> calls = [];

  void _enter(String name) {
    calls.add(name);
    if (offline) throw const FakeOfflineException();
  }

  @override
  Future<List<WorkoutTemplate>> fetchAll(String userId) async {
    _enter('fetchAll');
    return user;
  }

  @override
  Future<List<WorkoutTemplate>> fetchSystemTemplates() async {
    _enter('fetchSystemTemplates');
    return system;
  }

  @override
  Future<WorkoutTemplate?> fetchById(String id) async {
    _enter('fetchById');
    for (final t in [...user, ...system]) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  Future<void> create(WorkoutTemplate template) async => _enter('create');

  @override
  Future<void> update(WorkoutTemplate template) async => _enter('update');

  @override
  Future<void> delete(String id) async => _enter('delete');
}

Exercise _exercise(String id) => Exercise(
      id: id,
      name: '動作$id',
      categoryId: 'chest',
      type: ExerciseType.values.first,
      isSystem: true,
      isActive: true,
      createdAt: _t0,
      updatedAt: _t0,
    );

WorkoutTemplate _template(String id, {String? userId, bool isSystem = false}) => WorkoutTemplate(
      id: id,
      userId: userId,
      name: '模板$id',
      description: '說明',
      isSystem: isSystem,
      exercises: [
        TemplateExercise(
          id: '$id-e0',
          templateId: id,
          exerciseId: 'x1',
          exercise: _exercise('x1'),
          orderIndex: 0,
          suggestedSets: 3,
          suggestedReps: 10,
        ),
        TemplateExercise(
          id: '$id-e1',
          templateId: id,
          exerciseId: 'x2',
          exercise: _exercise('x2'),
          orderIndex: 1,
          suggestedSets: 4,
          suggestedReps: 8,
        ),
      ],
      createdAt: _t0,
      updatedAt: _t0,
    );

void main() {
  late SharedPreferences prefs;
  late _FakeCloudTemplates cloud;
  String? uid;

  OfflineCachedTemplateRepository repo() => OfflineCachedTemplateRepository(cloud, prefs, () => uid);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    cloud = _FakeCloudTemplates()
      ..user = [_template('u1', userId: 'uid-a')]
      ..system = [_template('s1', isSystem: true)];
    uid = 'uid-a';
  });

  test('線上讀過一次 → 離線(重建 repository)回快取,巢狀動作與順序完整', () async {
    await repo().fetchAll('uid-a');
    await repo().fetchSystemTemplates();
    cloud.offline = true;

    final user = await repo().fetchAll('uid-a');
    final system = await repo().fetchSystemTemplates();

    expect(user.single.id, 'u1');
    expect(user.single.name, '模板u1');
    expect(user.single.exercises.map((e) => e.exerciseId), ['x1', 'x2']);
    expect(user.single.exercises[1].suggestedReps, 8);
    expect(user.single.exercises[0].exercise?.name, '動作x1');
    expect(system.single.isSystem, isTrue);
  });

  test('離線 fetchById 從快取找;找不到拋原錯誤', () async {
    await repo().fetchAll('uid-a');
    await repo().fetchSystemTemplates();
    cloud.offline = true;

    expect((await repo().fetchById('s1'))?.name, '模板s1');
    expect((await repo().fetchById('u1'))?.exercises.length, 2);
    await expectLater(repo().fetchById('nope'), throwsA(isA<FakeOfflineException>()));
  });

  test('沒有快取時離線拋原錯誤', () async {
    cloud.offline = true;
    await expectLater(repo().fetchAll('uid-a'), throwsA(isA<FakeOfflineException>()));
  });

  test('快取以 uid 區隔:A 的模板不會給 B', () async {
    await repo().fetchAll('uid-a');
    cloud.offline = true;
    uid = 'uid-b';
    await expectLater(repo().fetchAll('uid-b'), throwsA(isA<FakeOfflineException>()));
  });

  test('寫入直接委派,離線照舊失敗', () async {
    cloud.offline = true;
    await expectLater(repo().create(_template('n1', userId: 'uid-a')), throwsA(isA<FakeOfflineException>()));
    expect(cloud.calls, ['create']);
  });
}
