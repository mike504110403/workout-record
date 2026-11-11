// 未完成草稿檢查(原本在 workout_page.dart 首次進入訓練分頁時跳)。訓練分頁
// 拿掉、改成從首頁進入的全螢幕模式後,這個檢查搬到 App 殼層:登入完成進到
// 首頁後檢查一次(router.dart `_AppShellState` 掛載時呼叫)。選「繼續」就
// 接手草稿並進入全螢幕訓練頁;選「放棄」就刪除草稿。
//
// 對照 .claude/decisions/2026-08-04-波3訓練流草稿寫穿與系統模板.md:
// `WorkoutController.build()` 刻意不自動接手上一個 session 的草稿,由使用者
// 在這個對話框明確決定。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dashboard/dashboard_controller.dart';
import 'workout_controller.dart';
import 'workout_launcher.dart';

Future<void> promptRecoverableDraft(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(workoutControllerProvider.notifier);
  final draft = await controller.checkForRecoverableDraft();
  if (!context.mounted || draft == null) return;
  // 草稿已經在 state 裡(例如使用者先從全螢幕訓練頁返回首頁,殼層才掛上)
  // ——不必再問,也不能拿 DB 的舊版本蓋掉。
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
  if (!context.mounted) return;

  try {
    if (resume == true) {
      await controller.resumeDraft(draft.id);
      if (!context.mounted) return;
      if (ref.read(workoutControllerProvider).value?.draft != null) {
        openCurrentWorkout(context);
      }
    } else if (ref.read(workoutControllerProvider).value?.draft?.id == draft.id) {
      // 對話框開著的期間,同一筆草稿已被接手、正在使用(例如直開 `/workout`
      // 的進頁檢查先接手了)——刪掉會把使用者正在記的訓練整筆清掉。改成
      // 進入該草稿。
      openCurrentWorkout(context);
    } else {
      await controller.discardRecoverableDraft(draft.id);
      // 首頁的「繼續訓練」標籤是首頁 controller 從 DB 查的;草稿刪掉後要
      // 重查,首頁才會變回「開始訓練」(殼層 index 沒變,router 不會代勞)。
      ref.invalidate(dashboardControllerProvider);
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('處理未完成訓練失敗:$e')));
  }
}
