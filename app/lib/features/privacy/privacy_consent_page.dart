// 隱私同意浮層。文案逐字對照 iOS
// `ios/WorkoutRecord/WorkoutRecord/Sources/Views/Privacy/PrivacyConsentView.swift`
// (該文案已符合「資料存本機」現狀,不得自行改寫)。
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

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Icon(
              Icons.front_hand,
              size: 50,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              '隱私權同意',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '使用前請閱讀並同意以下條款',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _TermsSection(
                      title: '資料收集範圍',
                      items: [
                        'Apple ID 登入資訊(姓名、電子郵件)',
                        '應用程式使用數據與操作行為',
                        '設備資訊與錯誤報告',
                        '訓練記錄僅儲存於您的裝置本機',
                      ],
                    ),
                    SizedBox(height: 24),
                    _TermsSection(
                      title: '資料使用目的',
                      items: [
                        '提供帳號登入功能',
                        '改善應用程式功能與用戶體驗',
                        '分析與修復技術問題',
                        '提供更符合需求的服務',
                      ],
                    ),
                    SizedBox(height: 24),
                    _TermsSection(
                      title: '隱私保護承諾',
                      items: [
                        '訓練記錄儲存在您的裝置本機,不會上傳雲端',
                        '僅收集必要的帳號資訊',
                        '不用於廣告或行銷目的',
                        '不與第三方分享您的個人資料',
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CheckboxRow(
                    key: const Key('analyticsConsentCheckbox'),
                    value: _analyticsAgreed,
                    text: '我同意收集匿名使用數據以改善服務',
                    onChanged: (value) => setState(() => _analyticsAgreed = value),
                  ),
                  _CheckboxRow(
                    key: const Key('privacyConsentCheckbox'),
                    value: _privacyAgreed,
                    text: '我已閱讀並同意隱私政策',
                    onChanged: (value) => setState(() => _privacyAgreed = value),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('agreeAndContinueButton'),
                      onPressed: _bothAgreed ? _handleAgreeAndContinue : null,
                      child: const Text('同意並繼續'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('declineButton'),
                    onPressed: _handleDecline,
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('不同意'),
                  ),
                ],
              ),
            ),
          ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: Theme.of(context).textTheme.bodyMedium),
                Expanded(child: Text(item, style: Theme.of(context).textTheme.bodyMedium)),
              ],
            ),
          ),
      ],
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
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              value ? Icons.check_box : Icons.check_box_outline_blank,
              color: value ? Theme.of(context).colorScheme.primary : Colors.grey,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
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
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block, size: 48, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  '需要您的同意才能繼續使用',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'WorkoutRecord 需要您同意隱私權條款才能提供服務。'
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
