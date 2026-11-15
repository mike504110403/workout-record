// 組間休息倒數的緊湊頂端列(對照 iOS `RestTimerHeaderView`,見
// `ios/WorkoutRecord/WorkoutRecord/Sources/Views/Workout/RestTimerView.swift:218-291`)。
// 只在計時進行中(`RestTimerState.isVisible`)顯示,不佔版面。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_tokens.dart';
import 'rest_timer_controller.dart';

class RestTimerBar extends ConsumerStatefulWidget {
  const RestTimerBar({super.key});

  @override
  ConsumerState<RestTimerBar> createState() => _RestTimerBarState();
}

class _RestTimerBarState extends ConsumerState<RestTimerBar> {
  /// 結束提示顯示多久後自動消失。
  static const _bannerDuration = Duration(seconds: 4);

  Timer? _bannerTimer;

  /// 非 null = 正在顯示結束提示(內容為提示文字)。
  String? _bannerText;

  @override
  void dispose() {
    _bannerTimer?.cancel();
    super.dispose();
  }

  void _showBanner(String? exerciseName) {
    _bannerTimer?.cancel();
    _bannerTimer = Timer(_bannerDuration, _dismissBanner);
    setState(() {
      _bannerText = exerciseName != null ? '休息結束・準備下一組 $exerciseName' : '休息結束・準備下一組';
    });
  }

  void _dismissBanner() {
    _bannerTimer?.cancel();
    _bannerTimer = null;
    if (mounted && _bannerText != null) setState(() => _bannerText = null);
  }

  @override
  Widget build(BuildContext context) {
    // 自然倒數結束 → 在原計時列位置顯示列內提示(對照 iOS `WorkoutView.swift:77-92`
    // 的 alert;iOS 手動調到 0 也會跳,這裡與震動一致只在自然結束時跳)。不用
    // showDialog/SnackBar:不擋畫面,也不跟別處共用的 ScaffoldMessenger 互搶。
    ref.listen<int>(restTimerControllerProvider.select((s) => s.finishedCount), (prev, next) {
      if (prev == null || next <= prev) return;
      _showBanner(ref.read(restTimerControllerProvider).exerciseName);
    });
    // 結束後又開始新一輪休息 → 提示立即消失,換回倒數列。
    ref.listen<bool>(restTimerControllerProvider.select((s) => s.isRunning), (prev, next) {
      if (next) _dismissBanner();
    });
    final timer = ref.watch(restTimerControllerProvider);
    if (!timer.isVisible) {
      final bannerText = _bannerText;
      return bannerText == null ? const SizedBox.shrink() : _buildBanner(context, bannerText);
    }

    final minutes = timer.remainingSeconds ~/ 60;
    final seconds = timer.remainingSeconds % 60;
    final timeText = '$minutes:${seconds.toString().padLeft(2, '0')}';

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final controller = ref.read(restTimerControllerProvider.notifier);
    // 三個控制鈕的點擊區一律至少 48x48(IconButton/TextButton 預設在部分
    // 平台/密度下會縮到 40),明確指定而不靠全域 theme。
    final iconButtonStyle = IconButton.styleFrom(
      minimumSize: const Size.square(kMinInteractiveDimension),
      tapTargetSize: MaterialTapTargetSize.padded,
    );

    return Container(
      key: const Key('restTimerBar'),
      color: colors.primaryContainer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: timer.progress, minHeight: 3),
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.pageHorizontal, right: AppSpacing.xs),
            child: Row(
              children: [
                Icon(Icons.timer_outlined, color: colors.onPrimaryContainer),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '休息 $timeText',
                  key: const Key('restTimerRemainingText'),
                  style: AppNumberStyles.body(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600, color: colors.onPrimaryContainer),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (timer.exerciseName != null)
                  Expanded(
                    child: Text(
                      timer.exerciseName!,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.onPrimaryContainer),
                    ),
                  )
                else
                  const Spacer(),
                IconButton(
                  key: const Key('restTimerMinus15Button'),
                  tooltip: '減 15 秒',
                  style: iconButtonStyle,
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => controller.adjust(-15),
                ),
                IconButton(
                  key: const Key('restTimerPlus15Button'),
                  tooltip: '加 15 秒',
                  style: iconButtonStyle,
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => controller.adjust(15),
                ),
                TextButton(
                  key: const Key('restTimerSkipButton'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.square(kMinInteractiveDimension),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  onPressed: controller.skip,
                  child: const Text('跳過'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBanner(BuildContext context, String text) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      key: const Key('restFinishedBanner'),
      color: colors.primaryContainer,
      child: InkWell(
        onTap: _dismissBanner,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageHorizontal),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, color: colors.onPrimaryContainer),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    text,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
