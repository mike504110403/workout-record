// 開始畫面(對照 iOS `StartWorkoutView`,見
// ios/WorkoutRecord/WorkoutRecord/Sources/Views/Workout/WorkoutView.swift:98-150)。
// 「開始自由訓練」/「從模板開始」/「模板管理」三個入口,見波 3 brief
// A 節與 .claude/decisions/2026-08-04-波3訓練流草稿寫穿與系統模板.md 補裁④
// (模板頁導覽入口屬第二段/workout tab 範圍)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'templates/template_picker_sheet.dart';
import 'templates/templates_list_page.dart';
import 'workout_controller.dart';

class StartWorkoutView extends ConsumerStatefulWidget {
  const StartWorkoutView({super.key});

  @override
  ConsumerState<StartWorkoutView> createState() => _StartWorkoutViewState();
}

class _StartWorkoutViewState extends ConsumerState<StartWorkoutView> {
  bool _isStarting = false;

  Future<void> _startFree() async {
    if (_isStarting) return;
    setState(() => _isStarting = true);
    try {
      await ref.read(workoutControllerProvider.notifier).startFreeWorkout();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('開始訓練失敗:$e')));
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  Future<void> _startFromTemplate() async {
    if (_isStarting) return;
    final applied = await showTemplatePicker(context);
    if (applied == null || !mounted) return;

    setState(() => _isStarting = true);
    try {
      await ref.read(workoutControllerProvider.notifier).startFromTemplate(applied);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('開始訓練失敗:$e')));
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  void _openTemplateManagement() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TemplatesListPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fitness_center, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('開始新的訓練', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('選擇訓練模板或自由訓練', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            SizedBox(
              width: 280,
              child: FilledButton.icon(
                key: const Key('startFreeWorkoutButton'),
                onPressed: _isStarting ? null : _startFree,
                icon: const Icon(Icons.add_circle),
                label: const Text('開始自由訓練'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 280,
              child: OutlinedButton.icon(
                key: const Key('startFromTemplateButton'),
                onPressed: _isStarting ? null : _startFromTemplate,
                icon: const Icon(Icons.description_outlined),
                label: const Text('從模板開始'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 280,
              child: TextButton.icon(
                key: const Key('manageTemplatesButton'),
                onPressed: _openTemplateManagement,
                icon: const Icon(Icons.list_alt),
                label: const Text('模板管理'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
