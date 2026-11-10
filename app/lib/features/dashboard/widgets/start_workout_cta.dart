// 首頁首屏唯一主 CTA:全寬 FilledButton。有進行中的訓練草稿時改成「繼續訓練」。
// 其餘次要動作(記錄體重、查看進度)下放到各自所屬的卡片(體重卡、本週卡)。
import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';

class StartWorkoutCta extends StatelessWidget {
  const StartWorkoutCta({
    super.key,
    required this.hasDraftWorkout,
    required this.onPressed,
  });

  /// 是否有進行中的訓練草稿(`DashboardState.hasDraftWorkout`)。
  final bool hasDraftWorkout;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppSizes.buttonHeight,
      child: FilledButton.icon(
        key: const Key('quickActionStartWorkout'),
        onPressed: onPressed,
        icon: Icon(hasDraftWorkout ? Icons.play_arrow : Icons.fitness_center),
        label: Text(hasDraftWorkout ? '繼續訓練' : '開始訓練'),
      ),
    );
  }
}
