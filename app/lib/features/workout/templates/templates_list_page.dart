// 模板列表頁:分區顯示系統/個人模板,提供新增/編輯/刪除入口。對照 iOS
// 設定底下管理模板的畫面。系統模板不顯示編輯/刪除按鈕(對照 brief:系統
// 模板不可編輯/刪除)。
//
// 卡片內容對照 iOS WorkoutTemplateView.swift 的 `TemplateCard`(:123 起):
// 描述、前 3 個動作各自「N 組 × M 次」、超過 3 個顯示「還有 N 個動作...」、
// 「使用此模板」按鈕(:209);空狀態「尚未建立模板」+「建立第一個模板」
// (:43、:57)。「使用此模板」重用 WorkoutController.startFromTemplate
// (與訓練 tab「從模板開始」同一個方法),開始後導到訓練 tab。
//
// 狀態快取生命週期:直接 watch templatesControllerProvider——
// create/update/delete 完成後 controller 內部一律呼叫 refresh(),Riverpod
// 自動重建這個畫面,不需要手動管理任何列表快取或下拉刷新邏輯。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/workout_template.dart';
import '../workout_controller.dart';
import 'applied_template.dart';
import 'section_header.dart';
import 'template_form_page.dart';
import 'templates_controller.dart';

class TemplatesListPage extends ConsumerStatefulWidget {
  const TemplatesListPage({super.key});

  @override
  ConsumerState<TemplatesListPage> createState() => _TemplatesListPageState();
}

class _TemplatesListPageState extends ConsumerState<TemplatesListPage> {
  bool _isStarting = false;

  void _openCreateForm() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TemplateFormPage()),
    );
  }

  Future<void> _confirmDelete(WorkoutTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除模板'),
        content: Text('確定要刪除「${template.name}」嗎?此動作無法復原。'),
        actions: [
          TextButton(
            key: const Key('templateDeleteCancelButton'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('templateDeleteConfirmButton'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(templatesControllerProvider.notifier).deleteTemplate(template);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('刪除模板失敗:$e')));
    }
  }

  /// 「使用此模板」:走與訓練 tab「從模板開始」相同的
  /// `WorkoutController.startFromTemplate(applyTemplate(...))`,完成後收掉
  /// 本頁堆疊並切到訓練 tab(對照 iOS MainTabView.swift:47-56 收到
  /// startWorkoutFromTemplate 通知後 selectedTab = 1)。已有進行中訓練時
  /// `startFromTemplate` 本身 no-op(既有行為),這裡不覆蓋它、只多提示一句
  /// 並同樣導到訓練 tab 讓使用者看到進行中的訓練。
  Future<void> _useTemplate(WorkoutTemplate template) async {
    if (_isStarting) return;
    setState(() => _isStarting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final router = GoRouter.maybeOf(context);
    try {
      final controller = ref.read(workoutControllerProvider.notifier);
      final hadDraft = (await ref.read(workoutControllerProvider.future)).draft != null;
      if (hadDraft) {
        messenger.showSnackBar(const SnackBar(content: Text('已有進行中的訓練,未套用此模板')));
      } else {
        await controller.startFromTemplate(applyTemplate(template));
      }
      if (!mounted) return;
      navigator.popUntil((route) => route.isFirst);
      router?.go('/workout');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('開始訓練失敗:$e')));
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(templatesControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('訓練模板'),
        actions: [
          IconButton(
            key: const Key('templateListAddButton'),
            icon: const Icon(Icons.add),
            onPressed: _openCreateForm,
          ),
        ],
      ),
      body: templatesAsync.when(
        data: (templates) {
          if (templates.isEmpty) {
            return _EmptyState(onCreate: _openCreateForm);
          }
          final systemTemplates = templates.systemTemplates;
          final personalTemplates = templates.personalTemplates;
          return ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              if (systemTemplates.isNotEmpty) ...[
                const TemplateSectionHeader('系統模板'),
                for (final template in systemTemplates)
                  _TemplateCard(
                    template: template,
                    onUse: _isStarting ? null : () => _useTemplate(template),
                  ),
              ],
              if (personalTemplates.isNotEmpty) ...[
                const TemplateSectionHeader('我的模板'),
                for (final template in personalTemplates)
                  _TemplateCard(
                    template: template,
                    onUse: _isStarting ? null : () => _useTemplate(template),
                    onEdit: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TemplateFormPage(existing: template),
                      ),
                    ),
                    onDelete: () => _confirmDelete(template),
                  ),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('載入模板失敗:$error')),
      ),
    );
  }
}

/// 空狀態,對照 iOS WorkoutTemplateView.swift:30-62。
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const Key('templateListEmptyState'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 60, color: theme.colorScheme.primary),
            const SizedBox(height: 20),
            Text(
              '尚未建立模板',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            Text(
              '建立訓練模板來快速開始訓練',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('templateEmptyCreateButton'),
              onPressed: onCreate,
              icon: const Icon(Icons.add_circle),
              label: const Text('建立第一個模板'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 模板卡片,對照 iOS `TemplateCard`(WorkoutTemplateView.swift:123-215)。
/// 預覽前 3 個動作;iOS 只在 suggestedSets 與 suggestedReps 皆有值時才顯示
/// 「N 組 × M 次」,這裡同。
class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, this.onUse, this.onEdit, this.onDelete});

  final WorkoutTemplate template;
  final VoidCallback? onUse;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  static const _previewCount = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final description = template.description;
    final preview = template.exercises.take(_previewCount).toList();
    final remaining = template.exercises.length - preview.length;

    return Card(
      key: Key('templateListTile_${template.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.name,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (description != null && description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          key: Key('templateCardDescription_${template.id}'),
                          style: secondary,
                        ),
                      ],
                    ],
                  ),
                ),
                if (!template.isSystem)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: Key('templateEditButton_${template.id}'),
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: onEdit,
                      ),
                      IconButton(
                        key: Key('templateDeleteButton_${template.id}'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: onDelete,
                      ),
                    ],
                  ),
              ],
            ),
            const Divider(height: 24),
            Text('動作', style: secondary),
            const SizedBox(height: 4),
            for (var i = 0; i < preview.length; i++)
              Padding(
                key: Key('templateCardExercise_${template.id}_$i'),
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        preview[i].exercise?.name ?? '',
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (preview[i].suggestedSets != null && preview[i].suggestedReps != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${preview[i].suggestedSets} 組 × ${preview[i].suggestedReps} 次',
                        style: secondary,
                      ),
                    ],
                  ],
                ),
              ),
            if (remaining > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '還有 $remaining 個動作...',
                  key: Key('templateCardMore_${template.id}'),
                  style: secondary,
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: Key('templateUseButton_${template.id}'),
                onPressed: onUse,
                icon: const Icon(Icons.play_arrow),
                label: const Text('使用此模板'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
