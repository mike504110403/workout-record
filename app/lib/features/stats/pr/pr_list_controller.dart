// PR 排行頁的資料組裝與狀態控制。對應 iOS 版
// `ios/WorkoutRecord/WorkoutRecord/Sources/ViewModels/PRViewModel.swift` 的
// 資料載入部分(不含肌群篩選——brief 範圍只要求分組列出,不含篩選 UI)。
//
// userId 解析:與 powerlifting_controller.dart 同一套組合慣例(dashboard
// 的 session→UserRepository 查證 + exercise_picker 的血緣 fallback),見
// 該檔案開頭注解。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/personal_record.dart';
import '../../../data/providers.dart';
import '../../auth/session_controller.dart';
import '../../auth/resolve_user_id.dart';

class PrListState {
  const PrListState({this.summaries = const []});

  final List<PRSummary> summaries;
}

class PrListController extends AsyncNotifier<PrListState> {
  @override
  Future<PrListState> build() {
    ref.watch(sessionControllerProvider.select((s) => s.appleUserId));
    return _load();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  Future<PrListState> _load() async {
    final userId = await _resolveUserId();
    if (userId == null) return const PrListState();

    final repo = ref.read(personalRecordRepositoryProvider);
    final summaries = await repo.getPRSummary(userId);
    return PrListState(summaries: summaries);
  }

  Future<String?> _resolveUserId() => resolveSessionUserIdWithImportFallback(ref);
}

final prListControllerProvider =
    AsyncNotifierProvider<PrListController, PrListState>(PrListController.new);
