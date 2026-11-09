// 對「本機 Supabase」(supabase start)的真實分頁驗證。預設跳過;執行:
//   LOCAL_SUPABASE_URL=http://127.0.0.1:55421 LOCAL_SUPABASE_ANON_KEY=<本機 anon key> \
//     flutter test test/data/supabase/supabase_pagination_local_test.dart
// 會在本機庫註冊一個臨時使用者、灌 2500 筆體重與 1200 場訓練,驗證 PostgREST
// 真的有 1000 列上限、而 repository 取得完整資料。只連本機,不碰遠端。
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workout_record/data/repositories/supabase/supabase_body_weight_repository.dart';
import 'package:workout_record/data/repositories/supabase/supabase_workout_repository.dart';

String _uuid(int n) => '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

void main() {
  final url = Platform.environment['LOCAL_SUPABASE_URL'];
  final key = Platform.environment['LOCAL_SUPABASE_ANON_KEY'];
  final enabled = url != null && key != null && url.contains('127.0.0.1');

  test('本機 Supabase:>1000 筆分頁取完', () async {
    HttpOverrides.global = null; // flutter_test 預設擋網路
    final client = SupabaseClient(
      url!,
      key!,
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    );
    final email = 'page-${Random().nextInt(1 << 30)}@example.com';
    final auth = await client.auth.signUp(email: email, password: 'Passw0rd!pagination');
    expect(auth.session, isNotNull, reason: '本機需關閉 email confirm');

    const nBw = 2500, nWo = 1200;
    final base = DateTime.utc(2024);
    final now = DateTime.now().toUtc().toIso8601String();
    for (var s = 0; s < nBw; s += 500) {
      await client.from('body_weights').insert([
        for (var i = s; i < s + 500; i++)
          {
            'id': _uuid(i),
            'weight': 70.0 + i / 100,
            // 每 5 筆同一 measured_at,驗證 id 第二鍵讓翻頁確定性
            'measured_at': base.add(Duration(hours: i ~/ 5)).toIso8601String(),
            'created_at': now,
            'updated_at': now,
          },
      ]);
    }
    for (var s = 0; s < nWo; s += 400) {
      await client.from('workouts').insert([
        for (var i = s; i < s + 400; i++)
          {
            'id': _uuid(100000 + i),
            'started_at': base.add(Duration(hours: i ~/ 3)).toIso8601String(),
            'ended_at': base.add(Duration(hours: i ~/ 3, minutes: 30)).toIso8601String(),
            'total_volume': 10.0,
            'created_at': now,
            'updated_at': now,
          },
      ]);
    }

    // 基線:不分頁的 select 被伺服器截在 1000。
    final raw = await client.from('body_weights').select();
    // ignore: avoid_print
    print('[local] raw select body_weights = ${raw.length}');
    expect(raw.length, 1000);

    final bw = await SupabaseBodyWeightRepository(client).fetchAll();
    // ignore: avoid_print
    print('[local] fetchAll body_weights = ${bw.length}');
    expect(bw.length, nBw);
    expect({for (final r in bw) r.id}.length, nBw);
    for (var i = 1; i < bw.length; i++) {
      final c = bw[i].measuredAt.compareTo(bw[i - 1].measuredAt);
      expect(c <= 0, isTrue);
      if (c == 0) expect(bw[i - 1].id.compareTo(bw[i].id) < 0, isTrue);
    }

    final recent = await SupabaseBodyWeightRepository(client).fetchRecent(1500);
    // ignore: avoid_print
    print('[local] fetchRecent(1500) = ${recent.length}');
    expect(recent.length, 1500);
    expect(recent.map((e) => e.id), bw.take(1500).map((e) => e.id));

    final wr = SupabaseWorkoutRepository(client);
    final vol = await wr.calculateTotalVolume();
    final all = await wr.fetchAll();
    // ignore: avoid_print
    print('[local] calculateTotalVolume = $vol, workouts fetchAll = ${all.length}');
    expect(vol, nWo * 10.0);
    expect(all.length, nWo);
    expect({for (final w in all) w.id}.length, nWo);

    await client.auth.signOut();
  }, skip: enabled ? false : '未設定 LOCAL_SUPABASE_URL / LOCAL_SUPABASE_ANON_KEY(本機 Supabase)',
      timeout: const Timeout(Duration(minutes: 3)));
}
