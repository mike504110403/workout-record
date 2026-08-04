// 模板列表頁:分區顯示系統/個人模板,提供新增/編輯/刪除入口。對照 iOS
// 設定底下管理模板的畫面。系統模板不顯示編輯/刪除按鈕(對照 brief:系統
// 模板不可編輯/刪除)。
//
// 狀態快取生命週期:直接 watch templatesControllerProvider——
// create/update/delete 完成後 controller 內部一律呼叫 refresh(),Riverpod
// 自動重建這個畫面,不需要手動管理任何列表快取或下拉刷新邏輯。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/workout_template.dart';
import 'template_form_page.dart';
import 'templates_controller.dart';

class TemplatesListPage extends ConsumerWidget {
  const TemplatesListPage({super.key});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    WorkoutTemplate template,
  ) async {
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
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('刪除模板失敗:$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(templatesControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('訓練模板'),
        actions: [
          IconButton(
            key: const Key('templateListAddButton'),
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TemplateFormPage()),
            ),
          ),
        ],
      ),
      body: templatesAsync.when(
        data: (templates) {
          if (templates.isEmpty) {
            return const Center(child: Text('尚無可用的模板'));
          }
          final systemTemplates = templates.where((t) => t.isSystem).toList();
          final personalTemplates = templates.where((t) => !t.isSystem).toList();
          return ListView(
            children: [
              if (systemTemplates.isNotEmpty) ...[
                const _SectionHeader('系統模板'),
                for (final template in systemTemplates) _TemplateTile(template: template),
              ],
              if (personalTemplates.isNotEmpty) ...[
                const _SectionHeader('我的模板'),
                for (final template in personalTemplates)
                  _TemplateTile(
                    template: template,
                    onEdit: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TemplateFormPage(existing: template),
                      ),
                    ),
                    onDelete: () => _confirmDelete(context, ref, template),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({required this.template, this.onEdit, this.onDelete});

  final WorkoutTemplate template;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('templateListTile_${template.id}'),
      title: Text(template.name),
      subtitle: Text('${template.exercises.length} 個動作'),
      trailing: template.isSystem
          ? null
          : Row(
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
    );
  }
}
