// 關於頁:版本號(package_info_plus)+ 隱私政策靜態內文。契約:zero-arg
// const 建構子、自帶 Scaffold/AppBar(同波 6 其他新頁面慣例)。
//
// 隱私文案紀律(repo CLAUDE.md 地雷區,brief 明定):必須與「登入後資料
// 存 Supabase 雲端、RLS 僅本人可讀寫」現狀一致;App 內沒有 analytics /
// crash SDK,文案不得宣稱收集使用數據或錯誤報告。參照 iOS `Views/About/AboutView.swift` 的
// `AboutPrivacyPolicyView` 內文精神(資訊收集/使用/安全/聯絡我們的段落
// 結構),但**不照抄**——那份文案本身跟 iOS 實作已經不一致(探路已證),照抄
// 會把同樣的病灶搬進 Flutter 版。事實陳述與 `privacy_consent_page.dart`、
// 隱私同意頁同源(2026-11 改為雲端現況;登入頁只留「隱私政策」連結,進 [PrivacyPolicyPage]);只宣稱 App 內真的有 UI 路徑的
// 功能(刪除帳號在設定頁;沒有匯出)。
//
// 版本號來源:`PackageInfo.fromPlatform()`,測試環境用
// `PackageInfo.setMockInitialValues` 提供固定值(package_info_plus 官方
// 測試慣例)。用 FutureBuilder 而非額外的 Riverpod controller——單純的
// 一次性平台查詢,沒有跨頁共用狀態或需要 invalidate 的快取,加一層
// controller 沒有實質好處。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/section_header.dart';
import '../tutorial/tutorial_page.dart';

/// 聯絡信箱(與 iOS AboutView 相同)。
const kContactEmail = 'mike504110403@gmail.com';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  /// 在 initState 建一次(review minor):放在 build 內會讓每次 rebuild(主題/
  /// MediaQuery 變動等)重新產生 Future,UI 閃回轉圈圈。
  ///
  /// 查詢失敗(理論上不該發生在真機——平台一定有 PackageInfo,只有測試環境沒
  /// mock 時的 MissingPluginException 才會走到這裡)包一層 try/catch 轉成
  /// null,而非讓整個 Future 帶著 error 完成:`snapshot.hasError` 不影響
  /// `connectionState`,若不特別處理,「data == null 就畫轉圈圈」的寫法在
  /// error 完成後會永遠卡在轉圈圈(動畫持續排新的 frame),`pumpAndSettle`
  /// 因此永遠等不到穩定,widget test 會 timeout。
  late final Future<PackageInfo?> _packageInfoFuture = _loadPackageInfo();

  static Future<PackageInfo?> _loadPackageInfo() async {
    try {
      return await PackageInfo.fromPlatform();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedStyle = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: const Text('關於')),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageHorizontal,
          vertical: AppSpacing.lg,
        ),
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: AppRadius.cardRadius,
              ),
              child: Icon(Icons.fitness_center, size: 36, color: theme.colorScheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Text(
              'Work It Out',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: FutureBuilder<PackageInfo?>(
              future: _packageInfoFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }
                final info = snapshot.data;
                if (info == null) {
                  return Text(
                    key: const Key('aboutVersionText'),
                    '版本未知',
                    style: mutedStyle,
                  );
                }
                return Text(
                  key: const Key('aboutVersionText'),
                  '版本 ${info.version} (${info.buildNumber})',
                  style: mutedStyle,
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: '隱私政策'),
          const AppCard(child: _PrivacySections()),
          const SizedBox(height: AppSpacing.sm),
          Text('如有任何隱私相關問題,請聯絡:$kContactEmail', style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: '功能特色'),
          const AppCard(
            child: Column(
              children: [
                _FeatureRow(
                  icon: Icons.bar_chart,
                  title: '數據分析',
                  description: '詳細的訓練數據分析與趨勢圖表',
                ),
                SizedBox(height: AppSpacing.md),
                _FeatureRow(
                  icon: Icons.emoji_events_outlined,
                  title: 'PR 追蹤',
                  description: '自動記錄各動作的個人最佳紀錄',
                ),
                SizedBox(height: AppSpacing.md),
                _FeatureRow(
                  icon: Icons.track_changes,
                  title: '目標追蹤',
                  description: '設定並追蹤您的健身目標',
                ),
                SizedBox(height: AppSpacing.md),
                _FeatureRow(
                  icon: Icons.fitness_center,
                  title: '三項力量',
                  description: '專業的深蹲、臥推、硬舉記錄',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  key: const Key('aboutContactTile'),
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('聯絡我們'),
                  subtitle: const Text(kContactEmail),
                  trailing: const Icon(Icons.copy, size: 18),
                  onTap: () async {
                    await Clipboard.setData(const ClipboardData(text: kContactEmail));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已複製聯絡信箱')),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('aboutTutorialTile'),
                  leading: const Icon(Icons.menu_book_outlined),
                  title: const Text('新手教學'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const TutorialPage()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('aboutTermsTile'),
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('服務條款'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const TermsOfServicePage()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('aboutDeveloperTile'),
                  title: const Text('開發者'),
                  trailing: Text('Mike Lin', style: mutedStyle),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.title, required this.description});

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 隱私政策全文頁——登入頁「隱私政策」連結的目的地(登入前沒有設定頁可進)。
/// 內文與關於頁內嵌的隱私政策是同一份 [_PrivacySections]。
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('隱私政策')),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageHorizontal,
          vertical: AppSpacing.lg,
        ),
        children: [
          const AppCard(child: _PrivacySections()),
          const SizedBox(height: AppSpacing.sm),
          Text('如有任何隱私相關問題,請聯絡:$kContactEmail', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _PrivacySections extends StatelessWidget {
  const _PrivacySections();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PrivacySection(
          title: '資料收集範圍',
          items: [
            'Apple ID 登入資訊(姓名、電子郵件)',
            '您輸入的訓練記錄、體重與健身目標等資料',
          ],
        ),
        SizedBox(height: AppSpacing.lg),
        _PrivacySection(
          title: '資料儲存方式',
          items: [
            '登入後,您的訓練記錄、體重與個人資料儲存於雲端伺服器(Supabase),並與您的 Apple 帳號綁定,用於跨裝置存取',
            '只有您本人登入後可以存取這些資料',
            '登出時會清除本機的個人資料,雲端帳號內的資料仍會保留',
            '可於「設定 > 刪除帳號」永久刪除帳號與雲端上的所有資料',
          ],
        ),
        SizedBox(height: AppSpacing.lg),
        _PrivacySection(
          title: '資料使用目的',
          items: [
            '提供帳號登入功能',
            '儲存您的訓練資料並提供跨裝置存取',
          ],
        ),
        SizedBox(height: AppSpacing.lg),
        _PrivacySection(
          title: '隱私保護承諾',
          items: [
            '僅收集必要的帳號資訊與您輸入的訓練資料',
            '不用於廣告或行銷目的',
            '不與第三方分享您的個人資料(雲端儲存服務 Supabase 僅代為儲存)',
          ],
        ),
      ],
    );
  }
}

class _PrivacySection extends StatelessWidget {
  const _PrivacySection({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: AppSpacing.sm),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: theme.textTheme.bodyMedium),
                Expanded(child: Text(item, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}

/// 服務條款(內容沿用 iOS `AboutView.swift` 的 TermsOfServiceView,「定期備份」
/// 一句改成雲端現況)。
class TermsOfServicePage extends StatelessWidget {
  const TermsOfServicePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String heading, String body) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(heading, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: AppSpacing.sm),
                Text(body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('服務條款')),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageHorizontal,
          vertical: AppSpacing.lg,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              '最後更新:2026 年 11 月 10 日',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          section('使用條款', '歡迎使用 Work It Out。使用本應用程式即表示您同意以下條款。'),
          section('服務說明', 'Work It Out 是一個健身記錄應用程式,幫助您追蹤訓練進度、記錄體重變化並分析健身數據。'),
          section('用戶責任', '• 提供準確的健身數據\n• 妥善保管您的登入帳號\n• 合理使用應用程式功能'),
          section('免責聲明', '本應用程式僅供參考,不應替代專業醫療建議。請在開始任何健身計劃前諮詢醫療專業人員。'),
          section('聯絡我們', '如有任何問題,請聯絡:$kContactEmail'),
        ],
      ),
    );
  }
}
