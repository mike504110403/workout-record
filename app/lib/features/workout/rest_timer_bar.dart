// 組間休息倒數的緊湊頂端列(對照 iOS `RestTimerHeaderView`,見
// `ios/WorkoutRecord/WorkoutRecord/Sources/Views/Workout/RestTimerView.swift:218-291`)。
// 只在計時進行中(`RestTimerState.isVisible`)顯示,不佔版面。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'rest_timer_controller.dart';

class RestTimerBar extends ConsumerWidget {
  const RestTimerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 自然倒數結束 → 提示框(對照 iOS `WorkoutView.swift:77-92`;iOS 手動調到 0
    // 也會跳,這裡與震動一致只在自然結束時跳)。
    ref.listen<int>(restTimerControllerProvider.select((s) => s.finishedCount), (prev, next) {
      if (prev == null || next <= prev) return;
      final name = ref.read(restTimerControllerProvider).exerciseName;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('restFinishedDialog'),
          title: const Text('休息時間結束'),
          content: Text(name != null ? '準備好進行下一組 $name 了嗎?' : '準備好進行下一組了嗎?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('知道了')),
          ],
        ),
      );
    });
    final timer = ref.watch(restTimerControllerProvider);
    if (!timer.isVisible) return const SizedBox.shrink();

    final minutes = timer.remainingSeconds ~/ 60;
    final seconds = timer.remainingSeconds % 60;
    final timeText =
        minutes > 0 ? '$minutes:${seconds.toString().padLeft(2, '0')}' : '${seconds}s';

    return Container(
      key: const Key('restTimerBar'),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: timer.progress, minHeight: 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined),
                const SizedBox(width: 8),
                Text('休息 $timeText', key: const Key('restTimerRemainingText')),
                const SizedBox(width: 8),
                if (timer.exerciseName != null)
                  Expanded(
                    child: Text(
                      timer.exerciseName!,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                else
                  const Spacer(),
                IconButton(
                  key: const Key('restTimerMinus15Button'),
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => ref.read(restTimerControllerProvider.notifier).adjust(-15),
                ),
                IconButton(
                  key: const Key('restTimerPlus15Button'),
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => ref.read(restTimerControllerProvider.notifier).adjust(15),
                ),
                TextButton(
                  key: const Key('restTimerSkipButton'),
                  onPressed: () => ref.read(restTimerControllerProvider.notifier).skip(),
                  child: const Text('跳過'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
