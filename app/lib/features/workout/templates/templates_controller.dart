// 訓練模板列表 + CRUD 狀態控制。對照 iOS
// `ViewModels/WorkoutTemplateViewModel.swift`。
//
// userId 解析比照 features/dashboard/dashboard_controller.dart 的
// `_resolveUserId` 既有慣例:目前使用者身分來自 sessionControllerProvider
// (SessionState.appleUserId),落地確認透過 UserRepository.getById——不新增
// 資料層方法、不碰 auth/session 檔案。
//
// 狀態快取生命週期:build() watch sessionControllerProvider.appleUserId,
// 換帳號時自動重跑;create/update/delete 成功後一律呼叫 [refresh],列表
// 立即重新載入,呼叫端(頁面)不需要自己手動刷新。失敗時維持舊資料
// (AsyncValue.guard 只在成功時才替換 state),並把錯誤往外拋——呼叫端
// (表單頁)自己 try/catch 顯示浮錯、解除 loading,見
// template_form_page.dart。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/uuid.dart';
import '../../../data/models/workout_template.dart';
import '../../../data/providers.dart';
import '../../auth/session_controller.dart';

class TemplatesController extends AsyncNotifier<List<WorkoutTemplate>> {
  @override
  Future<List<WorkoutTemplate>> build() {
    ref.watch(sessionControllerProvider.select((s) => s.appleUserId));
    return _load();
  }

  /// 新增個人模板。userId 一律是目前使用者(對照 onboarding
  /// `_ensureUserRow` 慣例解析)——系統模板的種子走
  /// app_database.dart 的 `_seedSystemTemplatesIfEmpty`,不透過這裡建立。
  Future<void> createTemplate({
    required String name,
    String? description,
    required List<TemplateExercise> exercises,
  }) async {
    final userId = await _resolveUserId();
    if (userId == null) {
      throw StateError(
        'TemplatesController.createTemplate: 無法解析目前使用者 userId'
        '(session 沒有已登入的 appleUserId,或 UserRepository.getById 查無此人)',
      );
    }
    final now = DateTime.now();
    final repo = ref.read(templateRepositoryProvider);
    await repo.create(
      WorkoutTemplate(
        id: generateUuidV4(),
        userId: userId,
        name: name,
        description: description,
        exercises: [
          for (var i = 0; i < exercises.length; i++)
            _withTemplateId(exercises[i], generateUuidV4(), i),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );
    await refresh();
  }

  /// 更新既有模板(對照 iOS:刪舊 exercises 整批重建,
  /// TemplateRepository.update 已如此實作)。系統模板一律拒絕——
  /// TemplateRepository.update 本身不檢查 isSystem(既有方法,brief 範圍
  /// 不動),保護放在這一層。
  Future<void> updateTemplate({
    required WorkoutTemplate existing,
    required String name,
    String? description,
    required List<TemplateExercise> exercises,
  }) async {
    if (existing.isSystem) {
      throw StateError('系統模板不可編輯:${existing.id}');
    }
    final repo = ref.read(templateRepositoryProvider);
    await repo.update(
      existing.copyWith(
        name: name,
        description: description,
        exercises: [
          for (var i = 0; i < exercises.length; i++)
            _withTemplateId(exercises[i], generateUuidV4(), i),
        ],
        updatedAt: DateTime.now(),
      ),
    );
    await refresh();
  }

  /// 刪除模板。系統模板一律拒絕——TemplateRepository.delete 的 WHERE
  /// 子句本來就排除 isSystem = true(既有方法,寫入 0 筆、不報錯),這裡
  /// 額外在呼叫前擋下並拋錯,讓 UI 能明確告知使用者「系統模板不可刪除」,
  /// 而不是默默沒反應。
  Future<void> deleteTemplate(WorkoutTemplate template) async {
    if (template.isSystem) {
      throw StateError('系統模板不可刪除:${template.id}');
    }
    final repo = ref.read(templateRepositoryProvider);
    await repo.delete(template.id);
    await refresh();
  }

  /// 對外重新整理;失敗時 state 落入 AsyncError,呼叫端(頁面)的
  /// `error:` 分支負責顯示重試 UI。
  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  Future<List<WorkoutTemplate>> _load() async {
    final repo = ref.read(templateRepositoryProvider);
    final userId = await _resolveUserId();
    final systemTemplates = await repo.fetchSystemTemplates();
    final personalTemplates =
        userId == null ? const <WorkoutTemplate>[] : await repo.fetchAll(userId);
    return [...systemTemplates, ...personalTemplates];
  }

  Future<String?> _resolveUserId() async {
    final sessionUserId = ref.read(sessionControllerProvider).appleUserId;
    if (sessionUserId == null || sessionUserId.isEmpty) return null;
    final userRepo = ref.read(userRepositoryProvider);
    final user = await userRepo.getById(sessionUserId);
    return user?.id;
  }

  TemplateExercise _withTemplateId(TemplateExercise exercise, String id, int orderIndex) {
    return TemplateExercise(
      id: id,
      templateId: exercise.templateId,
      exerciseId: exercise.exerciseId,
      orderIndex: orderIndex,
      suggestedSets: exercise.suggestedSets,
      suggestedReps: exercise.suggestedReps,
    );
  }
}

/// 分區小工具:對照 iOS `WorkoutTemplateViewModel.systemTemplates` /
/// `userTemplates` 計算屬性。
extension TemplatesListSections on List<WorkoutTemplate> {
  List<WorkoutTemplate> get systemTemplates => where((t) => t.isSystem).toList();
  List<WorkoutTemplate> get personalTemplates => where((t) => !t.isSystem).toList();
}

final templatesControllerProvider =
    AsyncNotifierProvider<TemplatesController, List<WorkoutTemplate>>(TemplatesController.new);
