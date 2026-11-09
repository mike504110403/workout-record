// Supabase repository 分頁:PostgREST 單次回應上限 1000 列,未分頁的「列出全部」
// 會被靜默截斷。這裡驗兩層:
// 1. [fetchAllPages] 純邏輯(fake 頁面來源):跨頁串接、邊界、maxRows。
// 2. 真 repository + 假 PostgREST(攔截 HTTP,實作 offset/limit/order 與
//    1000 列上限):超過一頁時取完、順序正確、排序含 id 第二鍵。
// 本機真 Supabase 實測見回報(supabase start 灌 >1000 筆)。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
// http 是 supabase_flutter 的傳遞依賴;測試只用它的 BaseClient 當 HTTP seam。
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workout_record/data/repositories/supabase/supabase_body_weight_repository.dart';
import 'package:workout_record/data/repositories/supabase/supabase_mapping.dart';
import 'package:workout_record/data/repositories/supabase/supabase_workout_repository.dart';

/// 極簡 PostgREST:單一資料表、全量資料放記憶體,支援 `order`、`limit`、`offset`
/// query 參數,回應列數封頂 [maxRows](模擬 Supabase 預設 max_rows=1000)。
class _FakePostgrest extends http.BaseClient {
  _FakePostgrest(this.rows);

  final List<Map<String, dynamic>> rows;
  static const maxRows = 1000;
  final requests = <Uri>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final q = request.url.queryParameters;
    requests.add(request.url);

    final sorted = [...rows];
    final order = q['order'];
    if (order != null) {
      final keys = order.split(',').map((e) => e.split('.')).toList();
      sorted.sort((a, b) {
        for (final k in keys) {
          final c = Comparable.compare(
            a[k[0]] as Comparable,
            b[k[0]] as Comparable,
          );
          if (c != 0) return k[1] == 'desc' ? -c : c;
        }
        return 0;
      });
    }
    final offset = int.tryParse(q['offset'] ?? '') ?? 0;
    final limit = int.tryParse(q['limit'] ?? '');
    final take = limit == null || limit > maxRows ? maxRows : limit;
    final page = sorted.skip(offset).take(take).toList();

    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(page))),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
      request: request,
    );
  }
}

SupabaseClient _client(http.Client fake) =>
    SupabaseClient('http://localhost:54321', 'anon-key', httpClient: fake);

String _id(int i) => 'id-${i.toString().padLeft(5, '0')}';

void main() {
  group('fetchAllPages(純邏輯)', () {
    PageFetcher source(int total, List<List<int>> calls) => (from, to) async {
          calls.add([from, to]);
          final end = to + 1 > total ? total : to + 1;
          return [
            for (var i = from; i < end; i++) {'i': i},
          ];
        };

    test('2500 列 pageSize 1000:三頁串接,順序保持', () async {
      final calls = <List<int>>[];
      final out = await fetchAllPages(source(2500, calls));
      expect(out.length, 2500);
      expect([for (final r in out) r['i']], List.generate(2500, (i) => i));
      expect(calls, [
        [0, 999],
        [1000, 1999],
        [2000, 2999],
      ]);
    });

    test('剛好 1000 列:多問一頁拿到空頁後結束,不漏不重', () async {
      final calls = <List<int>>[];
      final out = await fetchAllPages(source(1000, calls));
      expect(out.length, 1000);
      expect(calls.length, 2);
    });

    test('不足一頁:只打一次;空表回空', () async {
      final calls = <List<int>>[];
      expect((await fetchAllPages(source(7, calls))).length, 7);
      expect(calls.length, 1);
      expect(await fetchAllPages(source(0, [])), isEmpty);
    });

    test('maxRows 跨頁:最後一頁只要求剩餘列數', () async {
      final calls = <List<int>>[];
      final out = await fetchAllPages(
        source(5000, calls),
        pageSize: 1000,
        maxRows: 2300,
      );
      expect(out.length, 2300);
      expect(calls, [
        [0, 999],
        [1000, 1999],
        [2000, 2299],
      ]);
    });

    test('maxRows 大於資料量:取完即停', () async {
      final out = await fetchAllPages(source(1500, []), maxRows: 9999);
      expect(out.length, 1500);
    });
  });

  group('SupabaseBodyWeightRepository(假 PostgREST,2500 筆)', () {
    // measured_at 每 5 筆相同(製造同值,驗證 id 第二鍵讓翻頁確定性)。
    final rows = [
      for (var i = 0; i < 2500; i++)
        {
          'id': _id(i),
          'user_id': 'u1',
          'weight': 70.0 + i / 100,
          'measured_at': DateTime.utc(
            2024,
          ).add(Duration(hours: i ~/ 5)).toIso8601String(),
          'note': null,
          'is_synced': false,
          'created_at': '2024-01-01T00:00:00Z',
          'updated_at': '2024-01-01T00:00:00Z',
        },
    ];

    test('基線:不分頁的 select 只拿到 1000 筆(證明截斷真的存在)', () async {
      final fake = _FakePostgrest(rows);
      final raw = await _client(fake).from('body_weights').select();
      expect(raw.length, 1000);
    });

    test('fetchAll 取完 2500 筆,measured_at 降冪、同值以 id 升冪,無重複', () async {
      final fake = _FakePostgrest(rows);
      final result = await SupabaseBodyWeightRepository(
        _client(fake),
      ).fetchAll();

      expect(result.length, 2500);
      expect({for (final r in result) r.id}.length, 2500);
      for (var i = 1; i < result.length; i++) {
        final a = result[i - 1], b = result[i];
        final cmp = b.measuredAt.compareTo(a.measuredAt);
        expect(cmp <= 0, isTrue, reason: 'measured_at 必須降冪 @$i');
        if (cmp == 0) {
          expect(a.id.compareTo(b.id) < 0, isTrue, reason: '同值以 id 升冪 @$i');
        }
      }
      // 三個 HTTP 請求,offset 0/1000/2000,且每次都帶 id 第二排序鍵。
      expect(fake.requests.map((u) => u.queryParameters['offset']), [
        '0',
        '1000',
        '2000',
      ]);
      for (final u in fake.requests) {
        expect(
          u.queryParameters['order'],
          'measured_at.desc.nullslast,id.asc.nullslast',
        );
      }
    });

    test('fetchRecent(1500):跨頁取剛好 1500 筆(原本 limit>1000 會被截成 1000)', () async {
      final fake = _FakePostgrest(rows);
      final result = await SupabaseBodyWeightRepository(
        _client(fake),
      ).fetchRecent(1500);
      expect(result.length, 1500);
      expect(fake.requests.map((u) => u.queryParameters['limit']), [
        '1000',
        '500',
      ]);
    });

    test('fetchByDateRange 升冪排序 + id 第二鍵(請求層)', () async {
      final fake = _FakePostgrest(rows);
      await SupabaseBodyWeightRepository(
        _client(fake),
      ).fetchByDateRange(DateTime.utc(2000), DateTime.utc(2100));
      expect(
        fake.requests.first.queryParameters['order'],
        'measured_at.asc.nullslast,id.asc.nullslast',
      );
    });
  });

  group(
    'SupabaseWorkoutRepository.calculateTotalVolume(假 PostgREST,1800 場)',
    () {
      final rows = [
        for (var i = 0; i < 1800; i++)
          {
            'id': _id(i),
            'started_at': DateTime.utc(
              2024,
            ).add(Duration(hours: i)).toIso8601String(),
            'total_volume': 10.0,
          },
      ];

      test('1800 場全部加總 = 18000(未分頁只會得到 10000)', () async {
        final fake = _FakePostgrest(rows);
        final total = await SupabaseWorkoutRepository(
          _client(fake),
        ).calculateTotalVolume();
        expect(total, 18000.0);
        expect(fake.requests.length, 2);
        for (final u in fake.requests) {
          expect(
            u.queryParameters['order'],
            'started_at.desc.nullslast,id.asc.nullslast',
          );
        }
      });
    },
  );
}
