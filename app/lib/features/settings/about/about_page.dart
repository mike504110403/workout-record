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
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              '最後更新:2026 年 11 月 12 日',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          const AppCard(child: _PrivacySections()),
          const SizedBox(height: AppSpacing.sm),
          Text('如有任何隱私相關問題,請聯絡:$kContactEmail', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// 與 `docs/privacy.html`(線上版)同一份事實:兩邊要改一起改,內容不得互相矛盾。
/// 只寫有程式證據的陳述(不寫靜態加密、保存期限等沒有依據的承諾)。
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
            '帳號資訊:僅提供 Sign in with Apple 登入,我們會收到 Apple 提供的使用者識別碼、姓名(僅在您同意分享時)與電子郵件(可能是 Apple 隱藏信箱的轉寄地址)',
            '您輸入的訓練記錄(動作、組數、重量、次數、休息、備註)、模板、自訂動作、個人紀錄(PR)、體重與健身目標',
            '身高、性別、年齡,以及個人資料頁的姓名,只存放在這台裝置,不會上傳到我們的伺服器(可能包含在您自己的裝置備份中)',
            '注意:您在引導頁填寫的體重、目標體重與每週目標會上傳,分別成為雲端上的體重紀錄與健身目標',
            '若您用過舊版 iOS App,首次啟動會把裝置上的舊版資料匯入本機,登入後上傳到您自己的帳號',
            '本 App 不含任何分析、廣告、追蹤或當機回報工具',
          ],
        ),
        SizedBox(height: AppSpacing.lg),
        _PrivacySection(
          title: '資料使用目的',
          items: [
            '驗證身分,讓您登入自己的帳號',
            '儲存您的訓練資料,並提供跨裝置存取與統計',
            '不出售您的資料,也不用於廣告或行銷',
          ],
        ),
        SizedBox(height: AppSpacing.lg),
        _PrivacySection(
          title: '資料儲存與安全',
          items: [
            '登入後,您的訓練記錄、體重與帳號資訊儲存於雲端伺服器(Supabase),伺服器位於日本東京,與您的 Apple 帳號綁定,用於跨裝置存取',
            '資料以 HTTPS 傳輸;資料庫以列層級權限(RLS)限制每位使用者只能存取自己的資料,只有您本人登入後可以存取',
            '登入狀態儲存於 iOS Keychain(Android 為系統安全儲存)',
            '登出時會清除這台裝置上的登入狀態與個人資料設定;訓練資料快取、進行中的草稿與舊版匯入資料會保留,換帳號登入或刪除帳號時才會清除;雲端帳號內的資料仍會保留',
          ],
        ),
        SizedBox(height: AppSpacing.lg),
        _PrivacySection(
          title: '第三方服務',
          items: [
            'Supabase:雲端資料庫與帳號驗證,代為儲存您的資料',
            'Apple(Sign in with Apple):登入驗證',
          ],
        ),
        SizedBox(height: AppSpacing.lg),
        _PrivacySection(
          title: '您的權利與刪除帳號',
          items: [
            '您可以隨時登出,或在 App 內自行刪除帳號與所有資料',
            '刪除步驟:設定 > 刪除帳號,閱讀提示後兩次確認(此動作無法復原)',
            'iPhone 上會要求重新進行 Apple 授權以撤銷 Sign in with Apple 授權;若在此步驟取消,整個刪除會中止、不動任何資料',
            '完成後,雲端帳號與全部資料(訓練記錄、體重、目標、模板等)會被永久刪除,並清除這台裝置上的本機資料與舊版留下的資料檔',
            '若 Apple 授權撤銷失敗,帳號與資料仍會刪除,請到 iPhone 設定 > Apple ID > 使用 Apple 登入 手動移除本 App',
          ],
        ),
        SizedBox(height: AppSpacing.lg),
        _PrivacySection(
          title: '追蹤與廣告',
          items: [
            '不追蹤您在其他 App 或網站上的活動,不顯示任何廣告',
          ],
        ),
        SizedBox(height: AppSpacing.lg),
        _PrivacySection(
          title: '兒童隱私',
          items: [
            '本 App 不針對 13 歲以下兒童設計,不會故意收集其個人資訊',
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
