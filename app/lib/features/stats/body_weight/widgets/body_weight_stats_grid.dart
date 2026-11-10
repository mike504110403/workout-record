// 統計資訊卡片:當前體重、距目標、30 天變化三格。
//
// UI 優化波 2:原本六格(當前/目標/平均/最高/最低/變化)精簡成三格——目標值
// 已畫在趨勢圖上、平均/最高/最低是「體重」這種連續量少有人看的數字,留下最常
// 被問的「現在多少、離目標多遠、最近一個月往哪走」。`BodyWeightSummary` 仍保留
// 平均/最高/最低/變化欄位(純函式層不動),只是不再渲染。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/weight_format.dart' as weight_format;
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/metric_row.dart';
import '../../../../core/widgets/metric_tile.dart';
import '../../../settings/preferences/weight_unit.dart';
import '../body_weight_stats.dart';

class BodyWeightStatsGrid extends ConsumerWidget {
  const BodyWeightStatsGrid({super.key, required this.summary});

  final BodyWeightSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    // 三格等分一列(MetricRow),每格的值是「數字 + 小字單位」,在 390pt 寬手機
    // 上不會像舊的六格 GridView 那樣因固定長寬比而 overflow。
    return AppCard(
      key: const Key('bodyWeightStatsGrid'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
      child: MetricRow(
        tiles: [
          _tile(statKey: 'current', label: '當前', value: summary.current, unit: unit),
          _tile(statKey: 'toTarget', label: '距目標', value: summary.toTarget, unit: unit, signed: true),
          _tile(statKey: 'change30d', label: '30 天變化', value: summary.change30d, unit: unit, signed: true),
        ],
      ),
    );
  }

  /// [signed] 的數值帶正負號(正值＝增加、負值＝減少)。沒有值顯示「—」。
  MetricTile _tile({
    required String statKey,
    required String label,
    required double? value,
    required WeightUnit unit,
    bool signed = false,
  }) {
    final v = value;
    if (v == null) {
      return MetricTile(key: Key('bodyWeightStatCard-$statKey'), value: '—', label: label);
    }
    final number = weight_format.formatWeightValue(v, unit);
    return MetricTile(
      key: Key('bodyWeightStatCard-$statKey'),
      value: signed && v > 0 ? '+$number' : number,
      unit: unitSuffix(unit),
      label: label,
    );
  }
}
