// 「經典三項」子頁的資料組裝與狀態控制。對應 iOS 版
// `ios/WorkoutRecord/WorkoutRecord/Sources/ViewModels/PowerliftingViewModel.swift`。
//
// userId 解析:對照 dashboard_controller.dart 的 `_resolveUserId` 慣例
// (session → UserRepository 查證),再疊加 exercise_picker_controller.dart
// `_resolveUserId` 多出的「查無此人時退回血緣 key」那一段(見該檔案開頭
// 註解——CoreData 匯入的升級用戶,Users row 的 id 是
// `kCoreDataImportedUserIdKey` 指向的既有 row,不是這次登入的 session
// id)。brief 明確要求比照這個組合慣例,這裡只讀不寫(查無此人時回傳
// null,不像 onboarding 那樣新建 Users row)。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/uuid.dart';
import '../../../data/migration/coredata_importer_result.dart';
import '../../../data/models/personal_record.dart';
import '../../../data/models/power_lift_record.dart';
import '../../../data/providers.dart';
import '../../auth/session_controller.dart';
import '../../auth/shared_preferences_provider.dart';
import '../../workout/one_rm_calculator.dart';
import 'powerlifting_calculations.dart';

class PowerliftingState {
  const PowerliftingState({
    this.selectedLift = PowerLift.squat,
    this.manualRecords = const [],
    this.prSummaries = const [],
  });

  final PowerLift selectedLift;

  /// 目前使用者「所有」動作的手動紀錄(不只選取中的動作)——三項總和/
  /// 三項最佳成績卡需要同時看三個動作,不能只帶當前動作的子集。
  final List<PowerLiftRecord> manualRecords;

  /// 目前使用者「所有」動作的 PR 總結,用於依動作名稱篩出系統推估。
  final List<PRSummary> prSummaries;

  PowerliftingState copyWith({
    PowerLift? selectedLift,
    List<PowerLiftRecord>? manualRecords,
    List<PRSummary>? prSummaries,
  }) {
    return PowerliftingState(
      selectedLift: selectedLift ?? this.selectedLift,
      manualRecords: manualRecords ?? this.manualRecords,
      prSummaries: prSummaries ?? this.prSummaries,
    );
  }

  // MARK: - Derived (對照 iOS ViewModel 的 computed properties)

  List<PowerLiftRecord> get currentManualRecords =>
      manualRecordsForLift(manualRecords, selectedLift);

  PowerLiftRecord? get currentManualPR => bestManualRecord(manualRecords, selectedLift);

  List<PowerLiftRecord> get chartData => chartRecordsForLift(manualRecords, selectedLift);

  double get totalLiftsValue => totalLifts(manualRecords);

  PersonalRecord? get currentSystemPR => bestSystemEstimate(prSummaries, selectedLift);

  List<PRSummary> get currentSystemSummaries =>
      systemEstimatedSummaries(prSummaries, selectedLift);

  /// 三項最佳成績並列卡用:每個動作各自的最高 1RM(無紀錄則為 null,畫面
  /// 顯示「--」)。
  Map<PowerLift, PowerLiftRecord?> get bestByLift => {
        for (final lift in PowerLift.values) lift: bestManualRecord(manualRecords, lift),
      };
}

class PowerliftingController extends AsyncNotifier<PowerliftingState> {
  @override
  Future<PowerliftingState> build() {
    // 身分一變就重新載入(理由同 dashboard_controller.dart 的 build())。
    ref.watch(sessionControllerProvider.select((s) => s.appleUserId));
    return _load(selectedLift: PowerLift.squat);
  }

  /// 切換動作分頁——純粹的畫面狀態切換,不重新查 DB(三個動作的資料已經
  /// 一起載入在 state 裡)。
  void selectLift(PowerLift lift) {
    final current = state.value;
    if (current == null || current.selectedLift == lift) return;
    state = AsyncData(current.copyWith(selectedLift: lift));
  }

  Future<void> refresh() async {
    final selectedLift = state.value?.selectedLift ?? PowerLift.squat;
    state = await AsyncValue.guard(() => _load(selectedLift: selectedLift));
  }

  /// 手動新增三項紀錄(對照 iOS `addManualRecord`)。1RM 用波 3 共用的
  /// `calculateOneRepMax`,不重寫公式。
  ///
  /// userId 解析不到時拋例外(理論上不會發生,見檔案開頭注解)——呼叫端
  /// (AddPowerLiftRecordSheet)的 try/catch 會顯示錯誤、解除 loading,
  /// 不會誤以為寫入成功。
  Future<void> addManualRecord({
    required double weight,
    required int reps,
    required DateTime achievedAt,
    String? note,
  }) async {
    final userId = await _resolveUserId();
    if (userId == null) {
      throw StateError(
        'PowerliftingController.addManualRecord: 無法解析 userId'
        '(session 沒有已登入的 appleUserId、UserRepository.getById 查無此人,'
        '且沒有可用的 CoreData 匯入血緣 id)',
      );
    }

    final selectedLift = state.value?.selectedLift ?? PowerLift.squat;
    final now = DateTime.now();
    final repo = ref.read(powerLiftRecordRepositoryProvider);
    await repo.create(
      PowerLiftRecord(
        id: generateUuidV4(),
        userId: userId,
        lift: selectedLift,
        weight: weight,
        reps: reps,
        oneRepMax: calculateOneRepMax(weight: weight, reps: reps),
        achievedAt: achievedAt,
        note: note,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await refresh();
  }

  /// 刪除手動紀錄(對照 iOS `deleteManualRecord`)。刪除確認由呼叫端
  /// (widget 層)負責,這裡只做真正的刪除動作。
  Future<void> deleteManualRecord(String id) async {
    final repo = ref.read(powerLiftRecordRepositoryProvider);
    await repo.delete(id);
    await refresh();
  }

  Future<PowerliftingState> _load({required PowerLift selectedLift}) async {
    final userId = await _resolveUserId();
    if (userId == null) {
      return PowerliftingState(selectedLift: selectedLift);
    }

    final powerLiftRepo = ref.read(powerLiftRecordRepositoryProvider);
    final personalRecordRepo = ref.read(personalRecordRepositoryProvider);

    final manualRecords = await powerLiftRepo.getAll(userId);
    final prSummaries = await personalRecordRepo.getPRSummary(userId);

    return PowerliftingState(
      selectedLift: selectedLift,
      manualRecords: manualRecords,
      prSummaries: prSummaries,
    );
  }

  Future<String?> _resolveUserId() async {
    final userRepo = ref.read(userRepositoryProvider);

    final sessionUserId = ref.read(sessionControllerProvider).appleUserId;
    if (sessionUserId != null && sessionUserId.isNotEmpty) {
      final existing = await userRepo.getById(sessionUserId);
      if (existing != null) return existing.id;
    }

    final prefs = ref.read(sharedPreferencesProvider);
    final importedUserId = prefs.getString(kCoreDataImportedUserIdKey);
    if (importedUserId != null && importedUserId.isNotEmpty) {
      final imported = await userRepo.getById(importedUserId);
      if (imported != null) return imported.id;
    }

    return null;
  }
}

final powerliftingControllerProvider =
    AsyncNotifierProvider<PowerliftingController, PowerliftingState>(PowerliftingController.new);
