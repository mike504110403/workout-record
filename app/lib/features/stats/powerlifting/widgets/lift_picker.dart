// 動作 Picker(深蹲/槓鈴臥推/硬舉)。對應 iOS `PowerliftingView.liftPicker`
// 的 segmented picker。
import 'package:flutter/material.dart';

import '../../../../data/models/power_lift_record.dart';

const _liftLabels = {
  PowerLift.squat: '深蹲',
  PowerLift.benchPress: '槓鈴臥推',
  PowerLift.deadlift: '硬舉',
};

class LiftPicker extends StatelessWidget {
  const LiftPicker({super.key, required this.selected, required this.onSelected});

  final PowerLift selected;
  final ValueChanged<PowerLift> onSelected;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<PowerLift>(
      key: const Key('liftPicker'),
      segments: [
        for (final lift in PowerLift.values)
          ButtonSegment(value: lift, label: Text(_liftLabels[lift]!)),
      ],
      selected: {selected},
      onSelectionChanged: (selection) => onSelected(selection.first),
    );
  }
}
