// 隱私同意浮層。版面對照 iOS
// `ios/WorkoutRecord/WorkoutRecord/Sources/Views/Privacy/PrivacyConsentView.swift`;
// 文案已於 2026-11 改為雲端現況(登入後資料存 Supabase、僅本人可存取),
// 且不再宣稱收集 analytics / 錯誤報告(app/lib 沒有對應 SDK)。
//
// 兩個勾選框是這個頁面的本地狀態(對等 iOS `@State`),按下「同意並繼續」才
// 一次寫入 controller(見 privacy_consent_controller.dart 開頭註解)。
//
// 「不同意」:mobile 用 SystemNavigator.pop() 結束 App(對等 iOS
// `exit(0)`);web 沒有「結束網頁」這種操作,改顯示阻斷頁,不可用 exit(0)
// (dart:io Process.exit 在 web 也不存在)。
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_card.dart';
import 'privacy_consent_controller.dart';

class PrivacyConsentPage extends ConsumerStatefulWidget {
  const PrivacyConsentPage({super.key});

  @override
  ConsumerState<PrivacyConsentPage> createState() => _PrivacyConsentPageState();
}

class _PrivacyConsentPageState extends ConsumerState<PrivacyConsentPage> {
  bool _declined = false;
  bool _analyticsAgreed = false;
  bool _privacyAgreed = false;

  bool get _bothAgreed => _analyticsAgreed && _privacyAgreed;

  void _handleDecline() {
    if (kIsWeb) {
      setState(() => _declined = true);
    } else {
      SystemNavigator.pop();
    }
  }

  Future<void> _handleAgreeAndContinue() async {
    await ref.read(privacyConsentControllerProvider.notifier).agreeAndContinue();
  }

  @override
  Widget build(BuildContext context) {
    if (_declined) {
      return const _DeclinedBlockingPage();
    }

    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.xl),
                Icon(
                  Icons.privacy_tip_outlined,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '隱私權同意',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '使用前請閱讀並同意以下條款',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Expanded(
                  child: SingleChildScrollView(
                    padding: AppSpacing.pagePadding,
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TermsSection(
                          title: '資料收集範圍',
                          items: [
                            'Apple ID 登入資訊(姓名、電子郵件)',
                            '您輸入的訓練記錄、體重與健身目標等資料',
                            '登入後訓練資料儲存於雲端伺服器(Supabase),並與您的帳號綁定',
                          ],
                        ),
                        SizedBox(height: AppSpacing.md),
                        _TermsSection(
                          title: '資料使用目的',
                          items: [
                            '提供帳號登入功能',
                            '儲存您的訓練資料並提供跨裝置存取',
                          ],
                        ),
                        SizedBox(height: AppSpacing.md),
                        _TermsSection(
                          title: '隱私保護承諾',
                          items: [
                            '只有您本人登入後可以存取您的訓練資料',
                            '登出時會清除本機的個人資料',
                            '僅收集必要的帳號資訊與訓練資料',
                            '不用於廣告或行銷目的',
                            '不與第三方分享您的個人資料(雲端儲存服務 Supabase 僅代為儲存)',
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pageHorizontal,
                    AppSpacing.sm,
                    AppSpacing.pageHorizontal,
                    AppSpacing.sm,
                  ),
                  child: Column(
                    children: [
                      _CheckboxRow(
                        key: const Key('analyticsConsentCheckbox'),
                        value: _analyticsAgreed,
                        text: '我同意將訓練資料儲存於雲端伺服器以提供跨裝置存取',
                        onChanged: (value) => setState(() => _analyticsAgreed = value),
                      ),
                      _CheckboxRow(
                        key: const Key('privacyConsentCheckbox'),
                        value: _privacyAgreed,
                        text: '我已閱讀並同意隱私政策',
                        onChanged: (value) => setState(() => _privacyAgreed = value),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: const Key('agreeAndContinueButton'),
                          onPressed: _bothAgreed ? _handleAgreeAndContinue : null,
                          child: const Text('同意並繼續'),
                        ),
                      ),
                      TextButton(
                        key: const Key('declineButton'),
                        onPressed: _handleDecline,
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                        child: const Text('不同意'),
                      ),
                    ],
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

class _TermsSection extends StatelessWidget {
  const _TermsSection({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: theme.textTheme.bodyMedium),
                    Expanded(child: Text(item, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CheckboxRow extends StatelessWidget {
  const _CheckboxRow({
    required super.key,
    required this.value,
    required this.text,
    required this.onChanged,
  });

  final bool value;
  final String text;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: value,
      onChanged: (checked) => onChanged(checked ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _DeclinedBlockingPage extends StatelessWidget {
  const _DeclinedBlockingPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block, size: 48, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  '需要您的同意才能繼續使用',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Work It Out 需要您同意隱私權條款才能提供服務。'
                  '請關閉此分頁,或重新整理頁面以重新查看條款。',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
