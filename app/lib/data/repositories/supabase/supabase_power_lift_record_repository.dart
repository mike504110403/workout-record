import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/power_lift_record.dart';
import '../power_lift_record_repository.dart';
import 'supabase_mapping.dart';

/// [PowerLiftRecordRepository] 的 Supabase 實作。
///
/// 與 [DriftPowerLiftRecordRepository] 的差異:擁有者一律是登入者 auth uid,
/// 各方法的 userId 參數與 model 的 userId 不參與查詢/寫入(RLS 已限定本人)。
class SupabasePowerLiftRecordRepository implements PowerLiftRecordRepository {
  SupabasePowerLiftRecordRepository(this._client);

  final SupabaseClient _client;

  SupabaseQueryBuilder get _table => _client.from('power_lift_records');

  List<PowerLiftRecord> _parse(List<Map<String, dynamic>> rows) =>
      rows.map((j) => PowerLiftRecord.fromRow(powerLiftRecordRowFromJson(j))).toList();

  @override
  Future<PowerLiftRecord> create(PowerLiftRecord record) async {
    await _table.insert({
      ...companionToJson(record.toCompanion()),
      'user_id': requireUid(_client),
    });
    return record;
  }

  @override
  Future<List<PowerLiftRecord>> getAll(String userId) async {
    return _parse(await _table
        .select()
        .eq('user_id', requireUid(_client))
        .order('achieved_at', ascending: false));
  }

  @override
  Future<List<PowerLiftRecord>> getRecords(PowerLift lift, String userId) async {
    return _parse(await _table
        .select()
        .eq('user_id', requireUid(_client))
        .eq('lift', lift.value)
        .order('achieved_at', ascending: false));
  }

  @override
  Future<PowerLiftRecord?> getBestRecord(PowerLift lift, String userId) async {
    final row = await _table
        .select()
        .eq('user_id', requireUid(_client))
        .eq('lift', lift.value)
        .order('one_rep_max', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : PowerLiftRecord.fromRow(powerLiftRecordRowFromJson(row));
  }

  @override
  Future<PowerLiftRecord?> getById(String id) async {
    final row = await _table.select().eq('id', id).maybeSingle();
    return row == null ? null : PowerLiftRecord.fromRow(powerLiftRecordRowFromJson(row));
  }

  @override
  Future<PowerLiftRecord> update(PowerLiftRecord record) async {
    final rows = await _table
        .update({
          'weight': record.weight,
          'reps': record.reps,
          'one_rep_max': record.oneRepMax,
          'achieved_at': encodeValue(record.achievedAt),
          'note': record.note,
          'updated_at': encodeValue(DateTime.now()),
        })
        .eq('id', record.id)
        .select('id');
    if (rows.isEmpty) {
      throw StateError('記錄不存在: ${record.id}');
    }
    return record;
  }

  @override
  Future<void> delete(String id) async {
    final rows = await _table.delete().eq('id', id).select('id');
    if (rows.isEmpty) {
      throw StateError('記錄不存在: $id');
    }
  }

  @override
  Future<void> deleteAll(String userId) async {
    await _table.delete().eq('user_id', requireUid(_client));
  }
}
