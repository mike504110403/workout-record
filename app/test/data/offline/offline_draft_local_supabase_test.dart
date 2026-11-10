// 對「本機 Supabase」(supabase start)實測離線草稿的一次上傳 payload。預設跳過;執行:
//   LOCAL_SUPABASE_URL=http://127.0.0.1:55421 LOCAL_SUPABASE_ANON_KEY=<本機 anon key> \
//     flutter test test/data/offline/offline_draft_local_supabase_test.dart
// 註冊臨時使用者 → 本機草稿操作 → completeWorkout 經 create_workout 上傳 → 讀回比對
// 統計,並以 recompute_workout_summary(DB 端重算)交叉驗證;再模擬「回應遺失後重試」
// (同 id 再上傳一次 → 主鍵衝突 → 回查已完成 → 視為成功)確認雲端只有一筆。只連本機。
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workout_record/core/utils/uuid.dart';
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/repositories/offline/offline_draft_workout_repository.dart';
import 'package:workout_record/data/repositories/supabase/supabase_workout_repository.dart';

void main() {
  final url = Platform.environment['LOCAL_SUPABASE_URL'];
  final key = Platform.environment['LOCAL_SUPABASE_ANON_KEY'];
  final enabled = url != null && key != null && url.contains('127.0.0.1');

  test(
    '本機 Supabase:離線草稿完成時以 create_workout 一次上傳,重試不重複建立',
    () async {
      HttpOverrides.global = null; // flutter_test 預設擋網路
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final client = SupabaseClient(
        url!,
        key!,
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      );
      final email = 'offline-${Random().nextInt(1 << 30)}@example.com';
      final auth = await client.auth.signUp(
        email: email,
        password: 'Passw0rd!offline',
      );
      expect(auth.session, isNotNull, reason: '本機需關閉 email confirm');
      final uid = auth.user!.id;

      final exerciseRows = await client
          .from('exercises')
          .select('id, name')
          .eq('is_system', true)
          .limit(2);
      expect(exerciseRows, hasLength(2));

      final cloud = SupabaseWorkoutRepository(client);
      final repo = OfflineDraftWorkoutRepository(cloud, prefs);
      final now = DateTime.now();
      final startedAt = now.subtract(const Duration(minutes: 45, seconds: 20));
      final workoutId = generateUuidV4();
      final we1 = generateUuidV4();
      final we2 = generateUuidV4();

      await repo.create(
        Workout(
          id: workoutId,
          userId: uid,
          startedAt: startedAt,
          createdAt: now,
          updatedAt: now,
        ),
      );
      for (final (i, weId) in [we1, we2].indexed) {
        await repo.addExerciseToWorkout(
          WorkoutExercise(
            id: weId,
            workoutId: workoutId,
            exerciseId: exerciseRows[i]['id'] as String,
            exerciseName: exerciseRows[i]['name'] as String,
            orderIndex: i,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      WorkoutSet set(
        String weId,
        int n,
        double w,
        int r, {
        bool warmup = false,
      }) => WorkoutSet(
        id: generateUuidV4(),
        workoutExerciseId: weId,
        setNumber: n,
        weight: w,
        reps: r,
        rpe: 7.5,
        restSeconds: 90,
        isWarmup: warmup,
        createdAt: now,
        updatedAt: now,
      );
      final warmup = set(we1, 1, 20, 10, warmup: true);
      final s2 = set(we1, 2, 60, 8);
      final s3 = set(we1, 3, 999, 1);
      final s4 = set(we2, 1, 30.5, 12);
      for (final s in [warmup, s2, s3, s4]) {
        await repo.addSet(s);
      }
      await repo.updateSet(s2.copyWith(weight: 62.5, reps: 7));
      await repo.deleteSet(s3.id, workoutExerciseId: we1);
      await repo.setExerciseCompleted(we2, isCompleted: true);

      // 上傳前雲端沒有這筆(草稿只在本機)。
      expect(await cloud.fetchById(workoutId), isNull);
      final localDraft = (await repo.fetchDraft(uid))!;

      final endedAt = now;
      final completed = await repo.completeWorkout(workoutId, endedAt: endedAt);
      final uploaded = (await cloud.fetchById(workoutId))!;

      const expectedVolume = 62.5 * 7 + 30.5 * 12;
      for (final w in [completed, uploaded]) {
        expect(w.totalVolume, expectedVolume);
        expect(w.totalSets, 2);
        expect(w.totalExercises, 2);
        expect(w.duration, 45);
      }
      expect(uploaded.endedAt!.toUtc(), endedAt.toUtc());
      expect(uploaded.userId, uid);
      expect(uploaded.exercises.map((e) => e.id), [we1, we2]);
      expect(
        uploaded.exercises.first.sets.map(
          (s) => (s.setNumber, s.weight, s.reps, s.isWarmup),
        ),
        [(1, 20.0, 10, true), (2, 62.5, 7, false)],
      );
      expect(uploaded.exercises.last.isCompleted, isTrue);
      expect(uploaded.exercises.first.exercise?.name, exerciseRows[0]['name']);
      expect(await repo.fetchDraft(uid), isNull);

      // DB 端重算(recompute_workout_summary,暖身不計)與本機算的一致。
      final recomputed = await cloud.recomputeSummary(workoutId);
      expect(recomputed.totalVolume, expectedVolume);
      expect(recomputed.totalSets, 2);
      expect(recomputed.totalExercises, 2);

      // 回應遺失後重試:把同一份草稿放回本機再完成 → create_workout 主鍵衝突 →
      // 回查已完成 → 視為成功,雲端仍只有一筆。
      await OfflineDraftWorkoutRepository(cloud, prefs).create(localDraft);
      final retried = await repo.completeWorkout(
        workoutId,
        endedAt: endedAt.add(const Duration(minutes: 5)),
      );
      expect(retried.id, workoutId);
      expect(
        retried.endedAt!.toUtc(),
        endedAt.toUtc(),
        reason: '沿用雲端第一次的結果,不覆寫',
      );
      final count = await client
          .from('workouts')
          .count(CountOption.exact)
          .eq('id', workoutId);
      expect(count, 1);
      expect(await repo.fetchDraft(uid), isNull);

      await client.auth.signOut();
    },
    skip: enabled
        ? false
        : '需設定 LOCAL_SUPABASE_URL(127.0.0.1)/LOCAL_SUPABASE_ANON_KEY',
  );
}
