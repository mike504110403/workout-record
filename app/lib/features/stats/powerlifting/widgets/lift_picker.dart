// 動作 Picker(深蹲/槓鈴臥推/硬舉)。對應 iOS `PowerliftingView.liftPicker`。
//
// 介面改版:原本是整條 SegmentedButton(佔滿一列、視覺偏重),改成較輕的
// ChoiceChip 列;三顆 chip 靠左,右側保留給呼叫端放「新增」之類的操作鈕。
import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../data/models/power_lift_record.dart';
import '../powerlifting_format.dart';

class LiftPicker extends StatelessWidget {
  const LiftPicker({super.key, required this.selected, required this.onSelected, this.trailing});

  final PowerLift selected;
  final ValueChanged<PowerLift> onSelected;

  /// 同一列最右側的操作鈕(例如「新增」);null 則不佔位。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('liftPicker'),
      children: [
        Expanded(
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final lift in PowerLift.values)
                ChoiceChip(
                  key: Key('liftChip-${lift.name}'),
                  label: Text(powerLiftLabel(lift)),
                  selected: lift == selected,
                  showCheckmark: false,
                  onSelected: (_) => onSelected(lift),
                ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: AppSpacing.sm), trailing!],
      ],
    );
  }
}
