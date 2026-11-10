// 關於頁:版本號(package_info_plus)+ 隱私政策靜態內文。契約:zero-arg
// const 建構子、自帶 Scaffold/AppBar(同波 6 其他新頁面慣例)。
//
// 隱私文案紀律(repo CLAUDE.md 地雷區,brief 明定):必須與「登入後資料
// 存 Supabase 雲端、RLS 僅本人可讀寫」現狀一致;App 內沒有 analytics /
// crash SDK,文案不得宣稱收集使用數據或錯誤報告。參照 iOS `Views/About/AboutView.swift` 的
// `AboutPrivacyPolicyView` 內文精神(資訊收集/使用/安全/聯絡我們的段落
// 結構),但**不照抄**——那份文案本身跟 iOS 實作已經不一致(探路已證),照抄
// 會把同樣的病灶搬進 Flutter 版。事實陳述與 `privacy_consent_page.dart`、
// 登入頁隱私卡片同源(2026-11 改為雲端現況);只宣稱 App 內真的有 UI 路徑的
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
    return Scaffold(
      appBar: AppBar(title: const Text('關於')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Icon(Icons.fitness_center, size: 60, color: Colors.blue),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'WorkItOut',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
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
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  );
                }
                return Text(
                  key: const Key('aboutVersionText'),
                  '版本 ${info.version} (${info.buildNumber})',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                );
              },
            ),
          ),
          const SizedBox(height: 32),
          Text('隱私政策', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const _PrivacySection(
            title: '資料收集範圍',
            items: [
              'Apple ID 登入資訊(姓名、電子郵件)',
              '您輸入的訓練記錄、體重與健身目標等資料',
            ],
          ),
          const SizedBox(height: 20),
          const _PrivacySection(
            title: '資料儲存方式',
            items: [
              '登入後,您的訓練記錄、體重與個人資料儲存於雲端伺服器(Supabase),並與您的 Apple 帳號綁定,用於跨裝置存取',
              '只有您本人登入後可以存取這些資料',
              '登出時會清除本機的個人資料,雲端帳號內的資料仍會保留',
              '可於「設定 > 刪除帳號」永久刪除帳號與雲端上的所有資料',
            ],
          ),
          const SizedBox(height: 20),
          const _PrivacySection(
            title: '資料使用目的',
            items: [
              '提供帳號登入功能',
              '儲存您的訓練資料並提供跨裝置存取',
            ],
          ),
          const SizedBox(height: 20),
          const _PrivacySection(
            title: '隱私保護承諾',
            items: [
              '僅收集必要的帳號資訊與您輸入的訓練資料',
              '不用於廣告或行銷目的',
              '不與第三方分享您的個人資料(雲端儲存服務 Supabase 僅代為儲存)',
            ],
          ),
          const SizedBox(height: 20),
          Text('如有任何隱私相關問題,請聯絡:$kContactEmail', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 24),
          const Divider(),
          ListTile(
            key: const Key('aboutContactTile'),
            contentPadding: EdgeInsets.zero,
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
          ListTile(
            key: const Key('aboutTutorialTile'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('新手教學'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TutorialPage()),
            ),
          ),
          ListTile(
            key: const Key('aboutTermsTile'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: const Text('服務條款'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TermsOfServicePage()),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacySection extends StatelessWidget {
  const _PrivacySection({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('• $item'),
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
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(text, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('服務條款')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('最後更新:2026 年 11 月 10 日', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
          heading('使用條款'),
          const Text('歡迎使用 WorkItOut。使用本應用程式即表示您同意以下條款。'),
          heading('服務說明'),
          const Text('WorkItOut 是一個健身記錄應用程式,幫助您追蹤訓練進度、記錄體重變化並分析健身數據。'),
          heading('用戶責任'),
          const Text('• 提供準確的健身數據\n• 妥善保管您的登入帳號\n• 合理使用應用程式功能'),
          heading('免責聲明'),
          const Text('本應用程式僅供參考,不應替代專業醫療建議。請在開始任何健身計劃前諮詢醫療專業人員。'),
          heading('聯絡我們'),
          const Text('如有任何問題,請聯絡:$kContactEmail'),
        ],
      ),
    );
  }
}
