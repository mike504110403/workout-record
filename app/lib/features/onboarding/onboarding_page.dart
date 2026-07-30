// Onboarding 5 頁精靈。文案逐字對照 iOS
// `ios/WorkoutRecord/WorkoutRecord/Sources/Views/Onboarding/OnboardingView.swift`。
//
// iOS 用左右滑動(TabView(.page))切頁,Flutter 版改用明確的「下一步」/
// 「上一步」按鈕控頁(web 滑鼠沒有原生滑動手勢,按鈕在三平台都好測、好用)。
// 「跳過教學」在任一頁(除了最後一頁)都能直接完成 Onboarding,對等 iOS
// `onboardingState.complete()` 不做任何欄位驗證的行為。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'onboarding_controller.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _pageController = PageController();
  int _currentStep = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    _pageController.jumpToPage(step);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) => setState(() => _currentStep = index),
                children: const [
                  _WelcomeStep(),
                  _BasicInfoStep(),
                  _GoalsStep(),
                  _FeaturesStep(),
                  _CompleteStep(),
                ],
              ),
            ),
            _OnboardingBottomBar(
              currentStep: _currentStep,
              onBack: _currentStep > 0 ? () => _goToStep(_currentStep - 1) : null,
              onNext: () => _goToStep(_currentStep + 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingBottomBar extends ConsumerWidget {
  const _OnboardingBottomBar({
    required this.currentStep,
    required this.onBack,
    required this.onNext,
  });

  final int currentStep;
  final VoidCallback? onBack;
  final VoidCallback onNext;

  static const _lastStep = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(onboardingControllerProvider);
    final isLastStep = currentStep == _lastStep;
    // 對等 iOS `canProceed(from: .basicInfo)`:只有基本資訊頁(index 1)強制
    // 要求體重有效才能翻頁,其餘頁面都可以直接繼續。
    final canProceed = currentStep == 1 ? draft.isWeightValid : true;

    Future<void> completeOnboarding() =>
        ref.read(onboardingControllerProvider.notifier).complete();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (onBack != null)
            IconButton(
              key: const Key('onboardingBackButton'),
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            )
          else
            const SizedBox(width: 48),
          if (!isLastStep)
            TextButton(
              key: const Key('skipOnboardingButton'),
              onPressed: completeOnboarding,
              child: const Text('跳過教學'),
            ),
          if (isLastStep)
            FilledButton(
              key: const Key('startUsingButton'),
              onPressed: completeOnboarding,
              child: const Text('開始使用'),
            )
          else
            FilledButton(
              key: const Key('onboardingNextButton'),
              onPressed: canProceed ? onNext : null,
              child: const Text('下一步'),
            ),
        ],
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.icon, required this.title, required this.description});

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 80, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 24),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          description,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.icon, required this.title, required this.description});

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(description, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        children: const [
          _StepHeader(
            icon: Icons.waving_hand,
            title: '歡迎使用健身記錄',
            description: '讓我們快速了解如何使用這個應用程式來追蹤你的健身進度',
          ),
          SizedBox(height: 32),
          _FeatureCard(
            icon: Icons.fitness_center,
            title: '記錄訓練',
            description: '輕鬆記錄每次訓練的詳細數據',
          ),
          SizedBox(height: 12),
          _FeatureCard(
            icon: Icons.show_chart,
            title: '追蹤進度',
            description: '查看你的訓練進度和個人記錄',
          ),
          SizedBox(height: 12),
          _FeatureCard(
            icon: Icons.emoji_events,
            title: '成就系統',
            description: '解鎖各種成就,激勵持續訓練',
          ),
        ],
      ),
    );
  }
}

class _BasicInfoStep extends ConsumerWidget {
  const _BasicInfoStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(onboardingControllerProvider);
    final notifier = ref.read(onboardingControllerProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        children: [
          const _StepHeader(
            icon: Icons.person,
            title: '基本資訊',
            description: '請輸入你的基本資訊,幫助我們提供更好的訓練建議',
          ),
          const SizedBox(height: 32),
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Text('當前體重', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 4),
                const Text('*', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('onboardingWeightField'),
                  initialValue: draft.weightText,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(hintText: '請輸入體重'),
                  onChanged: notifier.setWeightText,
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<OnboardingWeightUnit>(
                key: const Key('onboardingWeightUnitToggle'),
                segments: const [
                  ButtonSegment(value: OnboardingWeightUnit.kg, label: Text('kg')),
                  ButtonSegment(value: OnboardingWeightUnit.lb, label: Text('lb')),
                ],
                selected: {draft.weightUnit},
                onSelectionChanged: (selection) => notifier.setWeightUnit(selection.first),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('身高', style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('onboardingHeightField'),
                  initialValue: draft.heightText,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(hintText: '請輸入身高(選填)'),
                  onChanged: notifier.setHeightText,
                ),
              ),
              const SizedBox(width: 12),
              const Text('cm'),
            ],
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('性別', style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            key: const Key('onboardingGenderToggle'),
            segments: const [
              ButtonSegment(value: '不指定', label: Text('不指定')),
              ButtonSegment(value: '男性', label: Text('男性')),
              ButtonSegment(value: '女性', label: Text('女性')),
            ],
            selected: {draft.gender},
            onSelectionChanged: (selection) => notifier.setGender(selection.first),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('年齡', style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('onboardingAgeField'),
            initialValue: draft.ageText,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '請輸入年齡(選填)'),
            onChanged: notifier.setAgeText,
          ),
        ],
      ),
    );
  }
}

class _GoalsStep extends ConsumerWidget {
  const _GoalsStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(onboardingControllerProvider);
    final notifier = ref.read(onboardingControllerProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        children: [
          const _StepHeader(
            icon: Icons.track_changes,
            title: '設定目標',
            description: '設定你的健身目標,讓訓練更有方向',
          ),
          const SizedBox(height: 32),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('目標體重', style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('onboardingTargetWeightField'),
                  initialValue: draft.targetWeightText,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(hintText: '請輸入目標體重(選填)'),
                  onChanged: notifier.setTargetWeightText,
                ),
              ),
              const SizedBox(width: 12),
              Text(draft.weightUnit.symbol),
            ],
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('每週訓練目標', style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('每週訓練'),
                Text(
                  '${draft.weeklyGoal} 次',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
                ),
                Row(
                  children: [
                    IconButton(
                      key: const Key('onboardingWeeklyGoalDecrement'),
                      onPressed: draft.weeklyGoal > 1
                          ? () => notifier.setWeeklyGoal(draft.weeklyGoal - 1)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    IconButton(
                      key: const Key('onboardingWeeklyGoalIncrement'),
                      onPressed: draft.weeklyGoal < 7
                          ? () => notifier.setWeeklyGoal(draft.weeklyGoal + 1)
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text('💡 小提示', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  '這些目標可以之後在設定中修改,不用擔心!',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturesStep extends StatelessWidget {
  const _FeaturesStep();

  static const _features = [
    (Icons.fitness_center, '訓練記錄', '記錄每次訓練'),
    (Icons.bar_chart, '數據分析', '查看訓練統計'),
    (Icons.calendar_month, '計劃安排', '規劃訓練計劃'),
    (Icons.emoji_events, '成就系統', '解鎖各種成就'),
    (Icons.track_changes, '目標設定', '設定健身目標'),
    (Icons.save, '本機儲存', '資料僅存於您的裝置'),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        children: [
          const _StepHeader(
            icon: Icons.star,
            title: '主要功能',
            description: '應用程式提供完整的健身記錄功能,包括訓練記錄、進度追蹤和成就系統',
          ),
          const SizedBox(height: 24),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.1,
            children: [
              for (final feature in _features)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(feature.$1, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 8),
                      Text(feature.$2, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        feature.$3,
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompleteStep extends StatelessWidget {
  const _CompleteStep();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Text(
            '🎉 準備就緒!',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            '你已經了解了所有主要功能,現在可以開始你的健身之旅了!',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text('💡 小提示', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  '記得定期記錄訓練數據,這樣才能更好地追蹤你的進步!',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
