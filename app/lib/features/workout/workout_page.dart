// 訓練 tab 入口。對照 iOS `WorkoutView`(見
// ios/WorkoutRecord/WorkoutRecord/Sources/Views/Workout/WorkoutView.swift:1-96)
// ——依 [WorkoutFlowState.draft] 是否存在切換開始畫面/進行中畫面,外加波 3
// 拍板的刻意差異:進入畫面時偵測未完成訓練草稿,詢問「繼續 / 放棄」(見
// .claude/decisions/2026-08-04-波3訓練流草稿寫穿與系統模板.md)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'start_workout_view.dart';
import 'workout_controller.dart';
import 'workout_in_progress_view.dart';

class WorkoutPage extends ConsumerStatefulWidget {
  const WorkoutPage({super.key});

  @override
  ConsumerState<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends ConsumerState<WorkoutPage> {
  bool _draftCheckStarted = false;

  @override
  void initState() {
    super.initState();
    // 等第一次畫面畫完再檢查——`showDialog` 需要一個已經掛上 Navigator/
    // Overlay 的 context,`initState` 當下這棵子樹還沒建好。
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForRecoverableDraft());
  }

  Future<void> _checkForRecoverableDraft() async {
    // 這個 State 在 App 存活期間只會呼叫一次(StatefulShellRoute.indexedStack
    // 讓 workout tab 分頁不會被 dispose,對照 router.dart 對 Dashboard 分頁
    // 的說明)——第一次進入 workout tab 或 App 剛啟動落在這個分頁時檢查
    // 一次,之後切分頁再切回來不會重複彈。
    if (_draftCheckStarted) return;
    _draftCheckStarted = true;

    final controller = ref.read(workoutControllerProvider.notifier);
    final draft = await controller.checkForRecoverableDraft();
    if (!mounted || draft == null) return;
    // 理論上不會發生(workout tab 剛進入、使用者不可能在這段 await 期間
    // 自己開始了另一筆訓練),防禦性地避免用舊草稿蓋過使用者剛建立的草稿。
    if (ref.read(workoutControllerProvider).value?.draft != null) return;

    final resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('發現未完成的訓練'),
          content: const Text('上次的訓練還沒有完成，要繼續嗎？'),
          actions: [
            TextButton(
              key: const Key('resumeDraftDiscardButton'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('放棄'),
            ),
            FilledButton(
              key: const Key('resumeDraftContinueButton'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('繼續上次訓練'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;

    try {
      if (resume == true) {
        await controller.resumeDraft(draft.id);
      } else {
        await controller.discardRecoverableDraft(draft.id);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('處理未完成訓練失敗:$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final flowAsync = ref.watch(workoutControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('訓練')),
      body: flowAsync.when(
        data: (flow) =>
            flow.draft != null ? const WorkoutInProgressView() : const StartWorkoutView(),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('載入失敗，請稍後再試'),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('workoutErrorRetryButton'),
                onPressed: () => ref.invalidate(workoutControllerProvider),
                child: const Text('重試'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
