// 全螢幕訓練頁(ui-polish 2026-11-11 Mike 裁示 4):shell 之外的 `/workout`
// 路由,沒有導覽列。由首頁經 workout_launcher.dart push 進來;完成或放棄後
// 回 `/dashboard`,返回(含 iOS 返回手勢)則保留草稿回到原本的分頁。
//
// 「未完成草稿 → 繼續/放棄」對話框已搬到 App 殼層
// (recoverable_draft_prompt.dart);這裡只處理「進來時 controller 沒有草稿」:
// `openCurrentWorkout` 拿不到 ref,controller 可能是 idle 但 DB 有草稿(換帳號、
// Web 直開 `/workout`、首頁標籤過期)——有就直接接手,沒有就回首頁。
// 舊的開始畫面(StartWorkoutView)已刪除,角色由首頁取代。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_tokens.dart';
import '../dashboard/dashboard_controller.dart';
import 'workout_controller.dart';
import 'workout_in_progress_view.dart';

/// 離開訓練頁回首頁(完成、放棄、找不到草稿)。首頁 index 沒變,router 的
/// 分頁切換失效點接不到,這裡先 invalidate 首頁再導過去——不然「記完訓練回
/// 首頁數字不更新」會回來(router.dart `shouldRefreshDashboardOnBranchSwitch`
/// 註解記錄的同一個坑)。
///
/// 先抓好 container 與 router 再做非同步動作:完成/放棄成功後 state 變
/// idle,發起的 widget 會被拆掉,之後不能再用它的 context/ref。
class WorkoutExit {
  WorkoutExit._(this._container, this._router);

  factory WorkoutExit.of(BuildContext context) =>
      WorkoutExit._(ProviderScope.containerOf(context, listen: false), GoRouter.maybeOf(context));

  final ProviderContainer _container;
  final GoRouter? _router;

  void toDashboard() {
    _container.invalidate(dashboardControllerProvider);
    _router?.go('/dashboard');
  }
}

/// 收起訓練頁(草稿保留):push 進來的就 pop 回原本的分頁(失效由
/// [WorkoutPage] 的 PopScope 處理);直開 `/workout` 沒有上一頁時改回首頁。
void minimizeWorkoutPage(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router != null && router.canPop()) {
    router.pop();
  } else {
    WorkoutExit.of(context).toDashboard();
  }
}

class WorkoutPage extends ConsumerStatefulWidget {
  const WorkoutPage({super.key, this.autoOpenPicker = false});

  /// 進頁後自動開選動作 sheet(launcher 的「開始空白訓練」才帶 true)。
  final bool autoOpenPicker;

  @override
  ConsumerState<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends ConsumerState<WorkoutPage> {
  /// 進頁檢查(找草稿)做完前顯示 loading,避免先閃一下空白頁又被導走。
  bool _entryResolved = false;

  @override
  void initState() {
    super.initState();
    // 等第一幀:showModalBottomSheet / go 都需要已掛上的 Navigator。
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveEntry());
  }

  Future<void> _resolveEntry() async {
    final controller = ref.read(workoutControllerProvider.notifier);
    try {
      var flow = await ref.read(workoutControllerProvider.future);
      if (flow.draft == null) {
        final recoverable = await controller.checkForRecoverableDraft();
        if (recoverable != null) await controller.resumeDraft(recoverable.id);
        flow = ref.read(workoutControllerProvider).value ?? flow;
      }
      if (!mounted) return;
      if (flow.draft == null) {
        await _leaveWithoutDraft();
        return;
      }
      setState(() => _entryResolved = true);
      if (widget.autoOpenPicker && flow.draft!.exercises.isEmpty) {
        await pickAndAddExercise(context, ref);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('載入訓練失敗:$e')));
      // 已經有草稿(例如錯誤發生在接手之後)就留下來顯示它;沒有草稿時這頁
      // 只會是一片空白,回首頁(首頁有「開始/繼續訓練」可重試)。
      if (ref.read(workoutControllerProvider).value?.draft != null) {
        setState(() => _entryResolved = true);
      } else {
        await _leaveWithoutDraft();
      }
    }
  }

  /// 進頁就發現沒草稿 → 回首頁,但要等這頁的進場轉場跑完才導。
  ///
  /// 直接 `go('/workout')`(Web 直開網址、舊的 go 入口)會把分頁殼那頁從
  /// root Navigator 換掉;被換掉的殼頁要等新頁進場動畫結束才真正拆除。進場
  /// 期間就 `go('/dashboard')`,新建的殼頁與還沒拆的舊殼頁同時掛著同一把
  /// `StatefulNavigationShell` GlobalKey → Duplicate GlobalKey,樹被截斷,首頁
  /// 整片空白只剩導覽列、直到切分頁才恢復(integrate 實測重現)。push 進來的
  /// 路徑殼頁一直在底下、不會撞,但等一下也無害。
  Future<void> _leaveWithoutDraft() async {
    final exit = WorkoutExit.of(context);
    final animation = ModalRoute.of(context)?.animation;
    if (animation != null && !animation.isCompleted) {
      final settled = Completer<void>();
      void onStatus(AnimationStatus status) {
        if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
          if (!settled.isCompleted) settled.complete();
        }
      }

      animation.addStatusListener(onStatus);
      await settled.future;
      animation.removeStatusListener(onStatus);
    }
    if (!mounted) return;
    exit.toDashboard();
  }

  @override
  Widget build(BuildContext context) {
    final flowAsync = ref.watch(workoutControllerProvider);

    return PopScope(
      // 返回(含 iOS 返回手勢、Android 返回鍵)= 收起訓練、草稿保留;回到的
      // 首頁要重查才會顯示「繼續訓練」與最新數字。
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) ref.invalidate(dashboardControllerProvider);
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: flowAsync.when(
            data: (flow) {
              if (flow.draft != null) return const WorkoutInProgressView();
              // 完成/放棄後 state 回到 idle,結算 sheet 蓋在上面、隨後回首頁——
              // 這段期間不畫任何東西。
              if (_entryResolved) return const SizedBox.shrink();
              return const Center(child: CircularProgressIndicator());
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('載入失敗，請稍後再試'),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    key: const Key('workoutErrorRetryButton'),
                    onPressed: () => ref.invalidate(workoutControllerProvider),
                    child: const Text('重試'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
