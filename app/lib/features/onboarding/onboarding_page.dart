// Onboarding 2 步精靈:1 基本資訊(單位、體重必填;身高、性別、年齡收進「更多」
// 可展開)、2 目標(目標體重、每週訓練次數,全為選填,可直接完成)。2026-11 改版:拿掉功能介紹頁與 emoji,版面
// 簡化為「頂部進度 + 單欄表單 + 固定底部主按鈕」。
//
// 用明確的「下一步」/ 返回按鈕控頁(web 滑鼠沒有原生滑動手勢)。「跳過」在
// 任一步都能直接完成 Onboarding,對等 iOS `onboardingState.complete()` 不做
// 任何欄位驗證的行為;但「下一步」要求體重為有效數值(對等 iOS
// `canProceed(from: .basicInfo)`)。資料寫入一律走
// [OnboardingController.complete],頁面不碰儲存邏輯。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_card.dart';
import 'onboarding_controller.dart';

const _stepCount = 2;

/// 表單最大寬度——web / 平板上避免欄位拉成整個視窗寬。
const _contentMaxWidth = 480.0;

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

  Future<void> _complete() => ref.read(onboardingControllerProvider.notifier).complete();

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingControllerProvider);
    final isLastStep = _currentStep == _stepCount - 1;
    // 只有基本資訊頁(index 0)強制要求體重有效才能翻頁。
    final canProceed = isLastStep || draft.isWeightValid;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            child: Column(
              children: [
                _OnboardingTopBar(
                  currentStep: _currentStep,
                  onBack: _currentStep > 0 ? () => _goToStep(_currentStep - 1) : null,
                  onSkip: _complete,
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (index) => setState(() => _currentStep = index),
                    children: const [
                      _BasicInfoStep(),
                      _GoalsStep(),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.sm,
                    AppSpacing.xl,
                    AppSpacing.lg,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: isLastStep
                        ? FilledButton(
                            key: const Key('startUsingButton'),
                            onPressed: _complete,
                            child: const Text('開始使用'),
                          )
                        : FilledButton(
                            key: const Key('onboardingNextButton'),
                            onPressed: canProceed ? () => _goToStep(_currentStep + 1) : null,
                            child: const Text('下一步'),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 頂列:返回(第 2 步才有)、「1 / 2」步驟指示、跳過;下方是細進度條。
class _OnboardingTopBar extends StatelessWidget {
  const _OnboardingTopBar({
    required this.currentStep,
    required this.onBack,
    required this.onSkip,
  });

  final int currentStep;
  final VoidCallback? onBack;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        0,
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 48,
                child: onBack == null
                    ? null
                    : IconButton(
                        key: const Key('onboardingBackButton'),
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back),
                      ),
              ),
              Expanded(
                child: Text(
                  '${currentStep + 1} / $_stepCount',
                  key: const Key('onboardingStepIndicator'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                key: const Key('skipOnboardingButton'),
                onPressed: onSkip,
                child: const Text('跳過'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: ClipRRect(
              borderRadius: AppRadius.chipRadius,
              child: LinearProgressIndicator(
                key: const Key('onboardingProgress'),
                value: (currentStep + 1) / _stepCount,
                minHeight: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 步驟標題區:小標(步驟名)+ 標題 + 一句說明。
class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.eyebrow, required this.title, required this.description});

  final String eyebrow;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          description,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _BasicInfoStep extends ConsumerWidget {
  const _BasicInfoStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(onboardingControllerProvider);
    final notifier = ref.read(onboardingControllerProvider.notifier);
    final unit = draft.weightUnit.symbol;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(
            eyebrow: '基本資訊',
            title: '歡迎使用 Work It Out',
            description: '先填寫基本資訊,幫助我們提供更貼近你的訓練建議',
          ),
          const SizedBox(height: AppSpacing.xl),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FieldLabel('單位'),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<OnboardingWeightUnit>(
                    key: const Key('onboardingWeightUnitToggle'),
                    segments: const [
                      ButtonSegment(value: OnboardingWeightUnit.kg, label: Text('kg')),
                      ButtonSegment(value: OnboardingWeightUnit.lb, label: Text('lb')),
                    ],
                    selected: {draft.weightUnit},
                    onSelectionChanged: (selection) => notifier.setWeightUnit(selection.first),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  key: const Key('onboardingWeightField'),
                  initialValue: draft.weightText,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: '當前體重(必填)', suffixText: unit),
                  onChanged: notifier.setWeightText,
                ),
                const SizedBox(height: AppSpacing.sm),
                // 身高/性別/年齡全是選填:預設收合,第一步只剩體重一個必要欄位。
                // ExpansionTile 預設收合時不建置 children,展開才出現。
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    key: const Key('onboardingMoreSection'),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    title: Text('更多資料(選填)', style: Theme.of(context).textTheme.titleSmall),
                    children: [
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        key: const Key('onboardingHeightField'),
                        initialValue: draft.heightText,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: '身高', suffixText: 'cm'),
                        onChanged: notifier.setHeightText,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const _FieldLabel('性別'),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          key: const Key('onboardingGenderToggle'),
                          segments: const [
                            ButtonSegment(value: '不指定', label: Text('不指定')),
                            ButtonSegment(value: '男性', label: Text('男性')),
                            ButtonSegment(value: '女性', label: Text('女性')),
                          ],
                          selected: {draft.gender},
                          onSelectionChanged: (selection) => notifier.setGender(selection.first),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      TextFormField(
                        key: const Key('onboardingAgeField'),
                        initialValue: draft.ageText,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '年齡', suffixText: '歲'),
                        onChanged: notifier.setAgeText,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ),
                ),
              ],
            ),
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
    final theme = Theme.of(context);
    final draft = ref.watch(onboardingControllerProvider);
    final notifier = ref.read(onboardingControllerProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(
            eyebrow: '目標',
            title: '設定你的目標',
            description: '讓訓練更有方向;這些目標之後都能在設定中修改',
          ),
          const SizedBox(height: AppSpacing.xl),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  key: const Key('onboardingTargetWeightField'),
                  initialValue: draft.targetWeightText,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: '目標體重(選填)',
                    suffixText: draft.weightUnit.symbol,
                  ),
                  onChanged: notifier.setTargetWeightText,
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(child: Text('每週訓練次數', style: theme.textTheme.titleSmall)),
                    IconButton(
                      key: const Key('onboardingWeeklyGoalDecrement'),
                      onPressed: draft.weeklyGoal > 1
                          ? () => notifier.setWeeklyGoal(draft.weeklyGoal - 1)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${draft.weeklyGoal} 次',
                        key: const Key('onboardingWeeklyGoalValue'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
        ],
      ),
    );
  }
}
