// Stats「體重」子頁的資料組裝與 CRUD 控制。對照 iOS 版
// `ios/WorkoutRecord/WorkoutRecord/Sources/ViewModels/BodyWeightViewModel.swift`。
//
// userId 解析沿用 dashboard_controller.dart 已建立的慣例：目前使用者身分
// 來自 `sessionControllerProvider`（SessionState.appleUserId），真正落地
// 確認透過 `UserRepository.getById` 查詢（不新增資料層方法、不碰
// auth/session 檔案）。查不到時一律視為「無使用者」，讓依賴 userId 的操作
// （新增紀錄）拋出可辨識的例外，讀取操作（目標體重）回退成 null，不拋錯
// 讓整頁掛掉——同 dashboard_controller.dart 對「理論上不會發生」狀態的
// 處理方式。
//
// 快取生命週期：`AsyncNotifierProvider` 沿用 dashboardControllerProvider
// 同款寫法——**不是** autoDispose，state 在沒有任何 listener 時仍常駐；
// 失效只有兩條路徑：
//   1. 顯式呼叫：CRUD（addEntry/updateEntry/deleteEntry）成功後一律呼叫
//      `refresh()` 重新查詢，讓列表/圖表/統計卡即時反映最新資料；載入失敗
//      時畫面提供的重試按鈕走 `ref.invalidate(bodyWeightTabControllerProvider)`
//      （對齊 dashboard_page.dart `dashboardErrorRetryButton` 的既有慣例）。
//   2. session 變動：`build()` 用 `ref.watch(sessionControllerProvider
//      .select((s) => s.appleUserId))` 訂閱身分變化，換帳號時 Riverpod
//      會自動重跑 build()。**但這只保證 `targetWeight` 換成新帳號的值**
//      （`UserGoalRepository.fetchByUser(userId)` 本身就是依 userId 查詢）——
//      `entriesDesc` 來自 `BodyWeightRepository.fetchAll()`，該方法**沒有
//      userId 過濾**（資料層既有行為，不在本波「不碰 repositories/」的範圍
//      內修），换帳號後列表/圖表看到的仍是全體使用者混在一起的體重紀錄，
//      不是「乾淨換帳號、不留前帳號快取」的完整保證，只是不會保留
//      *readonly 查詢結果* 的記憶體快取而已。
// 承接的 Stats 殼（stats_page.dart，工人 A 範圍）若要在「切走再切回」時
// 主動重新整理（對照 dashboard 側 router.dart 的 revisit invalidate 慣例），
// 需要在殼那邊另外掛 `ref.invalidate(bodyWeightTabControllerProvider)`——
// 這個 provider 本身不會自己在分頁切換時失效。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/uuid.dart';
import '../../../data/models/body_weight.dart';
import '../../../data/providers.dart';
import '../../auth/session_controller.dart';

class BodyWeightTabState {
  const BodyWeightTabState({
    this.entriesDesc = const [],
    this.targetWeight,
  });

  /// 新到舊排序（對照 `BodyWeightRepository.fetchAll()` 既有排序）——
  /// 紀錄列表直接使用；趨勢圖另外呼叫 `sortBodyWeightsAscending` 反轉，
  /// 不在這裡先轉成升序（列表跟圖表要的順序不同，state 只存一份、由各自
  /// 消費端各自轉換，避免存兩份容易失去同步的冗餘資料）。
  final List<BodyWeight> entriesDesc;

  /// 目標體重（`UserGoalRepository.fetchByUser(...).targetWeight`）。無
  /// 使用者身分或未設定目標時為 null。
  final double? targetWeight;
}

class BodyWeightTabController extends AsyncNotifier<BodyWeightTabState> {
  @override
  Future<BodyWeightTabState> build() {
    // 同 dashboard_controller.dart：watch 而非 read——換帳號時整份 state
    // 要用新 userId 重新組裝，不留前帳號快取。用 `.select` 只精準訂閱
    // `appleUserId` 欄位。
    ref.watch(sessionControllerProvider.select((s) => s.appleUserId));
    return _load();
  }

  /// 對外重新整理。CRUD 成功後、或呼叫端想手動刷新時呼叫。
  ///
  /// 刻意不主動先把 state 切成 `AsyncValue.loading()`（理由同
  /// dashboard_controller.dart 的 `refresh()`）——那樣會把舊資料整個丟掉，
  /// 新增/編輯/刪除完成的當下畫面會突然變成整頁 spinner。這裡讓 `_load()`
  /// await 期間 state 維持原本的 AsyncData，畫面照舊顯示舊資料直到新資料
  /// 就緒。
  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  /// 新增一筆體重紀錄並重新整理。
  ///
  /// userId 解析不到時（理論上不會發生，見檔案開頭註解）拋出例外而非靜默
  /// return——呼叫端（表單 sheet 的 `_save`）的 try/catch 會顯示錯誤、解除
  /// loading，不會誤以為寫入成功了照樣 pop 表單。
  Future<void> addEntry({
    required double weight,
    required DateTime measuredAt,
    String? note,
  }) async {
    final userId = await _resolveUserId();
    if (userId == null) {
      throw StateError(
        'BodyWeightTabController.addEntry: 無法解析 userId'
        '（session 沒有已登入的 appleUserId，或 UserRepository.getById 查無此人）',
      );
    }

    final now = DateTime.now();
    final repo = ref.read(bodyWeightRepositoryProvider);
    await repo.create(
      BodyWeight(
        id: generateUuidV4(),
        userId: userId,
        weight: weight,
        measuredAt: measuredAt,
        note: note,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await refresh();
  }

  /// 編輯既有一筆體重紀錄並重新整理。
  ///
  /// 刻意用「完整重建一個新的 BodyWeight 物件」而不是 `original.copyWith`
  /// ——`BodyWeight.copyWith` 對 `note` 走 `note ?? this.note` 的語意（傳
  /// null 代表「不改」），沒辦法用來把備註改成空字串／清空；這裡的
  /// [note] 直接對應表單當下的輸入值（含「使用者把備註欄清空」的情況），
  /// 要能忠實寫入 null，所以繞開 copyWith、直接建構整包物件交給
  /// `BodyWeightRepository.update`（它本來就吃完整物件，逐欄位寫入，不是
  /// 差量 patch）。
  ///
  /// `isSynced`/`updatedAt` 不需要在這裡自己算——`BodyWeightRepository.
  /// update()` 本身在 SQL 層寫死 `isSynced: false`、`updatedAt:
  /// Value(DateTime.now())`（見該方法），完全忽略傳入物件上的這兩個欄位。
  /// `updatedAt` 仍要填一個值只是因為 `BodyWeight` 建構子把它列為必填
  /// 參數，這裡沿用 [original.updatedAt] 當佔位值（`isSynced` 則直接省略、
  /// 吃建構子預設的 `false`），不佔位成看似有意義、實際上會被忽略的
  /// `DateTime.now()`，避免誤導未來的讀者以為這個值真的會被寫進 DB。
  Future<void> updateEntry({
    required BodyWeight original,
    required double weight,
    required DateTime measuredAt,
    String? note,
  }) async {
    final repo = ref.read(bodyWeightRepositoryProvider);
    await repo.update(
      BodyWeight(
        id: original.id,
        userId: original.userId,
        weight: weight,
        measuredAt: measuredAt,
        note: note,
        createdAt: original.createdAt,
        updatedAt: original.updatedAt,
      ),
    );
    await refresh();
  }

  /// 刪除一筆體重紀錄並重新整理。
  Future<void> deleteEntry(String id) async {
    final repo = ref.read(bodyWeightRepositoryProvider);
    await repo.delete(id);
    await refresh();
  }

  Future<BodyWeightTabState> _load() async {
    final repo = ref.read(bodyWeightRepositoryProvider);
    final entries = await repo.fetchAll();

    final userId = await _resolveUserId();
    final goalRepo = ref.read(userGoalRepositoryProvider);
    final goal = userId == null ? null : await goalRepo.fetchByUser(userId);

    return BodyWeightTabState(entriesDesc: entries, targetWeight: goal?.targetWeight);
  }

  Future<String?> _resolveUserId() async {
    final sessionUserId = ref.read(sessionControllerProvider).appleUserId;
    if (sessionUserId == null || sessionUserId.isEmpty) return null;
    final userRepo = ref.read(userRepositoryProvider);
    final user = await userRepo.getById(sessionUserId);
    return user?.id;
  }
}

final bodyWeightTabControllerProvider =
    AsyncNotifierProvider<BodyWeightTabController, BodyWeightTabState>(
  BodyWeightTabController.new,
);
