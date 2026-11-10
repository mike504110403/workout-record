// 設定主頁:section 化列表,對照 iOS `Views/Settings/SettingsView.swift:10-113`
// 取「真功能」子集(波 6 core brief seam 段;FEATURE_MAP Tab5 段是願景不是
// 基準——匯出/刪帳號/Google 登入等 iOS 全無實作,探路已證,不對照它做)。
// 七項入口:個人資料/目標設定/我的模板/偏好設定/關於/登出/ImportRetryTile,
// 依 iOS Section 精神分四組(個人/訓練/應用程式/帳號),組間以小標題區隔
// ——iOS 的 Section 有「動作庫管理」「通知」等本波不做的項,故只取子集分組。
//
// 目標設定(GoalSettingsPage)、我的模板(TemplatesListPage)、偏好設定
// (PreferencesPage,另一工人換真身的契約 stub)皆為 zero-arg const 頁面,
// push 慣例照 dashboard_page.dart:64 附近(GoalSettingsPage)與
// start_workout_view.dart:54 附近(TemplatesListPage)的既有寫法。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/cloud_auth.dart';
import '../auth/session_controller.dart';
import '../goals/goal_settings_page.dart';
import '../workout/templates/templates_list_page.dart';
import 'about/about_page.dart';
import 'preferences/preferences_page.dart';
import 'profile/profile_page.dart';
import 'widgets/cloud_upload_status_tile.dart';
import 'widgets/import_retry_tile.dart';

/// 分組小標題:列表內的輕量 section header(不用 Card,維持 ListTile 在
/// 一屏內可見——既有登出測試未捲動就點 signOutButton)。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.grey),
      ),
    );
  }
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('登出'),
        content: const Text('確定要登出嗎?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('登出'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(sessionControllerProvider.notifier).signOut();
    }
  }

  /// 刪除帳號:兩段確認(App Store 5.1.1(v))→ 呼叫雲端刪除。成功後
  /// session 清空,路由自動回登入頁;失敗只提示,本機不動。
  Future<void> _confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
    final first = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除帳號'),
        content: const Text('刪除後,你的帳號與所有訓練紀錄、體重、目標、模板都會從雲端永久刪除,'
            '這台裝置上的資料也會一併清除。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          TextButton(
            key: const Key('deleteAccountContinue'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('繼續', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (first != true || !context.mounted) return;

    final second = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確定要永久刪除?'),
        content: const Text('此動作無法復原。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          TextButton(
            key: const Key('deleteAccountConfirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('永久刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (second != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final ok = await ref.read(sessionControllerProvider.notifier).deleteAccount();
    if (navigator.mounted) navigator.pop();
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('刪除帳號失敗,請確認網路後再試一次')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          const _SectionHeader('個人'),
          ListTile(
            key: const Key('settingsProfileEntry'),
            leading: const Icon(Icons.person, color: Colors.blue),
            title: const Text('個人資料'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProfilePage()),
            ),
          ),
          ListTile(
            key: const Key('settingsGoalEntry'),
            leading: const Icon(Icons.track_changes, color: Colors.orange),
            title: const Text('目標設定'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const GoalSettingsPage()),
            ),
          ),
          const _SectionHeader('訓練'),
          ListTile(
            key: const Key('settingsTemplatesEntry'),
            leading: const Icon(Icons.description, color: Colors.teal),
            title: const Text('我的模板'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TemplatesListPage()),
            ),
          ),
          const _SectionHeader('應用程式'),
          ListTile(
            key: const Key('settingsPreferencesEntry'),
            leading: const Icon(Icons.settings, color: Colors.grey),
            title: const Text('偏好設定'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PreferencesPage()),
            ),
          ),
          ListTile(
            key: const Key('settingsAboutEntry'),
            leading: const Icon(Icons.info_outline, color: Colors.blueGrey),
            title: const Text('關於'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AboutPage()),
            ),
          ),
          const _SectionHeader('帳號'),
          ListTile(
            key: const Key('signOutButton'),
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('登出', style: TextStyle(color: Colors.red)),
            onTap: () => _confirmSignOut(context, ref),
          ),
          // 只有雲端帳號才有「帳號」可刪;本機模式不顯示。
          if (ref.watch(cloudAuthServiceProvider) != null)
            ListTile(
              key: const Key('deleteAccountButton'),
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('刪除帳號', style: TextStyle(color: Colors.red)),
              onTap: () => _confirmDeleteAccount(context, ref),
            ),
          // 僅在 CoreData 匯入永久失敗旗標為 true 時渲染,放列表尾。
          const ImportRetryTile(),
          // 雲端模式登入後本機舊資料上傳的狀態(idle 不渲染)。
          const CloudUploadStatusTile(),
        ],
      ),
    );
  }
}
