import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/body_weight.dart';
import '../body_weight_repository.dart';
import 'supabase_mapping.dart';

/// [BodyWeightRepository] 的 Supabase 實作。
///
/// 與 [DriftBodyWeightRepository] 的差異:可見範圍由 RLS 限定為登入者本人;
/// 寫入時 `user_id` 一律覆寫成登入者 auth uid。其餘語義相同。
class SupabaseBodyWeightRepository implements BodyWeightRepository {
  SupabaseBodyWeightRepository(this._client);

  final SupabaseClient _client;

  SupabaseQueryBuilder get _table => _client.from('body_weights');

  List<BodyWeight> _parse(List<Map<String, dynamic>> rows) =>
      rows.map((j) => BodyWeight.fromRow(bodyWeightRowFromJson(j))).toList();

  @override
  Future<void> create(BodyWeight bodyWeight) async {
    await _table.insert({
      ...companionToJson(bodyWeight.toCompanion()),
      'user_id': requireUid(_client),
    });
  }

  @override
  Future<List<BodyWeight>> fetchAll() async {
    return _parse(await _table.select().order('measured_at', ascending: false));
  }

  @override
  Future<List<BodyWeight>> fetchByDateRange(DateTime from, DateTime to) async {
    return _parse(await _table
        .select()
        .gte('measured_at', encodeValue(from)!)
        .lte('measured_at', encodeValue(to)!)
        .order('measured_at', ascending: true));
  }

  @override
  Future<List<BodyWeight>> fetchRecent(int limit) async {
    return _parse(await _table.select().order('measured_at', ascending: false).limit(limit));
  }

  @override
  Future<void> update(BodyWeight bodyWeight) async {
    final rows = await _table
        .update({
          'weight': bodyWeight.weight,
          'measured_at': encodeValue(bodyWeight.measuredAt),
          'note': bodyWeight.note,
          'is_synced': false,
          'updated_at': encodeValue(DateTime.now()),
        })
        .eq('id', bodyWeight.id)
        .select('id');
    if (rows.isEmpty) {
      throw StateError('BodyWeight not found: ${bodyWeight.id}');
    }
  }

  @override
  Future<void> delete(String id) async {
    await _table.delete().eq('id', id);
  }

  @override
  Future<BodyWeight?> getLatestWeight() async {
    final row = await _table.select().order('measured_at', ascending: false).limit(1).maybeSingle();
    return row == null ? null : BodyWeight.fromRow(bodyWeightRowFromJson(row));
  }

  @override
  Future<double?> getAverageWeight(DateTime from, DateTime to) async {
    final weights = await fetchByDateRange(from, to);
    if (weights.isEmpty) return null;
    final sum = weights.fold<double>(0, (total, w) => total + w.weight);
    return sum / weights.length;
  }
}
