// 訓練入口契約(ui-polish 改版):首頁等其他畫面一律透過這三個函式開始或回到
// 訓練,不直接碰 workoutControllerProvider 或路由字串。
//
// 簽名由大腦訂定、跨工人共用,**不得改簽名**;實作由訓練流程切片負責。
// 訓練頁是 shell 之外的全螢幕路由(router.dart `/workout`):這裡一律 push
// 進去(返回/返回手勢回到原本的分頁),完成或放棄後由訓練頁自己回 `/dashboard`。
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'templates/applied_template.dart';
import 'workout_controller.dart';

/// 訓練頁路由路徑(router.dart 與這裡共用)。
const kWorkoutRoutePath = '/workout';

/// push 訓練頁時帶的參數(`GoRouter.push(extra:)`)。
@immutable
class WorkoutRouteArgs {
  const WorkoutRouteArgs({this.autoOpenPicker = false});

  /// 進頁後自動開選動作 sheet(只有「開始空白訓練」用)。
  final bool autoOpenPicker;
}

/// 開始中旗標:連點兩下「開始訓練」/模板 chip 時,第二次呼叫在第一次還在
/// 等 controller 寫入的期間進來——直接忽略,路由堆疊才不會疊兩層 `/workout`
/// (controller 的序列化鎖只保證不建兩筆草稿,擋不住兩次 push)。
bool _launching = false;

/// 目前最上層是不是已經是訓練頁(已在訓練頁再呼叫時不再 push)。
bool _isOnWorkoutPage(GoRouter router) {
  try {
    return router.state.matchedLocation == kWorkoutRoutePath;
  } catch (_) {
    return false;
  }
}

void _pushWorkoutPage(BuildContext context, {bool autoOpenPicker = false}) {
  final router = GoRouter.of(context);
  if (_isOnWorkoutPage(router)) return;
  router.push(kWorkoutRoutePath, extra: WorkoutRouteArgs(autoOpenPicker: autoOpenPicker));
}

Future<void> _launch(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function(WorkoutController controller) start, {
  required bool autoOpenPickerWhenEmpty,
}) async {
  if (_launching) return;
  _launching = true;
  try {
    await start(ref.read(workoutControllerProvider.notifier));
    if (!context.mounted) return;
    final draft = ref.read(workoutControllerProvider).value?.draft;
    if (draft == null) return;
    // 已有草稿時一律進既有草稿;只有「全新、還沒有動作」的空白訓練才自動開
    // 選動作 sheet(既有草稿已經有內容,自動彈 sheet 只會擋路)。
    _pushWorkoutPage(
      context,
      autoOpenPicker: autoOpenPickerWhenEmpty && draft.exercises.isEmpty,
    );
  } finally {
    _launching = false;
  }
}

/// 開始一個空白訓練並進入訓練畫面(自動開選動作 sheet);已有進行中的訓練
/// 則直接進入它。
Future<void> openFreeWorkout(BuildContext context, WidgetRef ref) => _launch(
  context,
  ref,
  (controller) => controller.startFreeWorkout(),
  autoOpenPickerWhenEmpty: true,
);

/// 用模板開始訓練並進入訓練畫面;已有進行中的訓練則直接進入它(不另建)。
Future<void> openTemplateWorkout(
  BuildContext context,
  WidgetRef ref,
  AppliedTemplate template,
) => _launch(
  context,
  ref,
  (controller) => controller.startFromTemplate(template),
  autoOpenPickerWhenEmpty: false,
);

/// 回到進行中的訓練畫面(呼叫端已確認有草稿)。拿不到 ref:controller 若
/// 還是 idle(換帳號、首頁標籤過期),由訓練頁進入時自己去 DB 找草稿
/// (workout_page.dart)。
void openCurrentWorkout(BuildContext context) => _pushWorkoutPage(context);
