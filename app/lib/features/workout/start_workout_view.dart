// 開始畫面(對照 iOS `StartWorkoutView`,見
// ios/WorkoutRecord/WorkoutRecord/Sources/Views/Workout/WorkoutView.swift:98-150)。
// 上方主按鈕「自由開始」,下方直接列出模板卡(點一下就以該模板開始,不再
// 經過「從模板開始」sheet),右上「模板管理」進管理頁。見波 3 brief A 節與
// .claude/decisions/2026-08-04-波3訓練流草稿寫穿與系統模板.md 補裁④
// (模板頁導覽入口屬第二段/workout tab 範圍)。
//
// `showTemplatePicker`(templates/template_picker_sheet.dart)仍保留作為
// 對外契約與既有測試對象,但開始畫面不再經過它。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/section_header.dart';
import '../../data/models/workout_template.dart';
import 'templates/applied_template.dart';
import 'templates/templates_controller.dart';
import 'templates/templates_list_page.dart';
import 'workout_controller.dart';

class StartWorkoutView extends ConsumerStatefulWidget {
  const StartWorkoutView({super.key});

  @override
  ConsumerState<StartWorkoutView> createState() => _StartWorkoutViewState();
}

class _StartWorkoutViewState extends ConsumerState<StartWorkoutView> {
  bool _isStarting = false;

  Future<void> _start(Future<void> Function() action) async {
    if (_isStarting) return;
    setState(() => _isStarting = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('開始訓練失敗:$e')));
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  Future<void> _startFree() => _start(
    () => ref.read(workoutControllerProvider.notifier).startFreeWorkout(),
  );

  Future<void> _startFromTemplate(WorkoutTemplate template) => _start(
    () => ref
        .read(workoutControllerProvider.notifier)
        .startFromTemplate(applyTemplate(template)),
  );

  void _openTemplateManagement() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const TemplatesListPage()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final templatesAsync = ref.watch(templatesControllerProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageHorizontal,
        AppSpacing.lg,
        AppSpacing.pageHorizontal,
        AppSpacing.xl,
      ),
      children: [
        FilledButton.icon(
          key: const Key('startFreeWorkoutButton'),
          onPressed: _isStarting ? null : _startFree,
          icon: const Icon(Icons.add),
          label: const Text('自由開始'),
        ),
        const SizedBox(height: AppSpacing.lg),
        SectionHeader(
          title: '從模板開始',
          trailing: TextButton.icon(
            key: const Key('manageTemplatesButton'),
            onPressed: _openTemplateManagement,
            icon: const Icon(Icons.list_alt),
            label: const Text('我的模板'),
          ),
        ),
        templatesAsync.when(
          data: (templates) {
            if (templates.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Text(
                  '還沒有模板,可以到「我的模板」建立。',
                  key: const Key('startTemplatesEmptyText'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            final personal = templates.personalTemplates;
            final system = templates.systemTemplates;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (personal.isNotEmpty) ..._section('我的模板', personal, theme),
                if (system.isNotEmpty) ..._section('系統模板', system, theme),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Text(
              '載入模板失敗,仍可使用「自由開始」。',
              key: const Key('startTemplatesErrorText'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _section(
    String title,
    List<WorkoutTemplate> templates,
    ThemeData theme,
  ) {
    return [
      Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.sm,
          bottom: AppSpacing.sm,
        ),
        child: Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      for (final template in templates) ...[
        _StartTemplateCard(
          template: template,
          onTap: _isStarting ? null : () => _startFromTemplate(template),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    ];
  }
}

/// 開始畫面上的模板卡:名稱、動作數、前三個動作名稱;整張可點,一鍵開始。
class _StartTemplateCard extends StatelessWidget {
  const _StartTemplateCard({required this.template, required this.onTap});

  final WorkoutTemplate template;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final names = [
      for (final e in template.exercises.take(3))
        if (e.exercise?.name case final name? when name.isNotEmpty) name,
    ];
    final remaining = template.exercises.length - 3;
    final summary = [
      '${template.exercises.length} 個動作',
      ...names,
      if (remaining > 0) '+$remaining',
    ].join(' · ');

    return AppCard(
      key: Key('startTemplateCard_${template.id}'),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(template.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Icon(Icons.play_circle_outline, color: colors.primary),
        ],
      ),
    );
  }
}
