// 選擇模板 sheet:分區顯示系統/個人模板,每個模板預覽前 3 個動作(對等 iOS
// TemplatePickerSheet,見
// ios/WorkoutRecord/WorkoutRecord/Sources/Views/Workout/WorkoutView.swift:483-645),
// 選定後回傳套用結果(applied_template.dart 的 applyTemplate)。
//
// 簽名固定不得改動(波 3 拆分決策的段間契約,見
// .claude/decisions/2026-08-04-波3訓練流草稿寫穿與系統模板.md——波 3 第二段
// 的訓練核心流會直接呼叫這個函式):
//   Future<AppliedTemplate?> showTemplatePicker(BuildContext context)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/workout_template.dart';
import 'applied_template.dart';
import 'section_header.dart';
import 'templates_controller.dart';

/// 見檔案開頭說明。使用者取消回傳 null。
Future<AppliedTemplate?> showTemplatePicker(BuildContext context) {
  return showModalBottomSheet<AppliedTemplate>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const _TemplatePickerSheet(),
  );
}

class _TemplatePickerSheet extends ConsumerWidget {
  const _TemplatePickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(templatesControllerProvider);

    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('選擇訓練模板'),
          leading: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          leadingWidth: 72,
        ),
        body: templatesAsync.when(
          data: (templates) {
            if (templates.isEmpty) {
              return const Center(child: Text('尚無可用的模板'));
            }
            final systemTemplates = templates.systemTemplates;
            final personalTemplates = templates.personalTemplates;
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (systemTemplates.isNotEmpty) ...[
                  const TemplateSectionHeader('系統模板'),
                  for (final template in systemTemplates)
                    _TemplatePickerCard(
                      template: template,
                      onSelect: () => Navigator.of(context).pop(applyTemplate(template)),
                    ),
                ],
                if (personalTemplates.isNotEmpty) ...[
                  const TemplateSectionHeader('我的模板'),
                  for (final template in personalTemplates)
                    _TemplatePickerCard(
                      template: template,
                      onSelect: () => Navigator.of(context).pop(applyTemplate(template)),
                    ),
                ],
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(child: Text('載入模板失敗:$error')),
        ),
      ),
    );
  }
}

class _TemplatePickerCard extends StatelessWidget {
  const _TemplatePickerCard({required this.template, required this.onSelect});

  final WorkoutTemplate template;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final preview = template.exercises.take(3).toList();
    final remaining = template.exercises.length - preview.length;

    return Card(
      key: Key('templatePickerCard_${template.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        key: Key('templatePickerCardTap_${template.id}'),
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(template.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (template.description != null) Text(template.description!),
              const SizedBox(height: 8),
              Text('${template.exercises.length} 個動作',
                  style: Theme.of(context).textTheme.bodySmall),
              for (final templateExercise in preview)
                Text(
                  '• ${templateExercise.exercise?.name ?? ''}'
                  '${templateExercise.suggestedSets != null && templateExercise.suggestedReps != null ? '(${templateExercise.suggestedSets} 組 x ${templateExercise.suggestedReps} 次)' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (remaining > 0)
                Text('還有 $remaining 個...', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
