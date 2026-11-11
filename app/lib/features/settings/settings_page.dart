// 設定主頁:section 化列表,對照 iOS `Views/Settings/SettingsView.swift:10-113`
// 取「真功能」子集(波 6 core brief seam 段;FEATURE_MAP Tab5 段是願景不是
// 基準——匯出/刪帳號/Google 登入等 iOS 全無實作,探路已證,不對照它做)。
// 七項入口:個人資料/目標設定/我的模板/偏好設定/關於/登出/ImportRetryTile,
// 依 iOS Section 精神分四組(個人/訓練/應用程式/帳號),組間以小標題區隔
// ——iOS 的 Section 有「動作庫管理」「通知」等本波不做的項,故只取子集分組。
// 後續補上「自定義動作」入口(訓練組,iOS 在「動作庫管理」組):管理自建動作的
// 列表/新增/編輯/刪除,見 custom_exercises/。
//
// UI 改版(第 3 波):每組一張群組卡片
// (SectionHeader + AppCard + ListTile),圖示一律單色;「重量單位」「主題」從偏好
// 子頁拉到「應用程式」組的行內 SegmentedButton,偏好子頁保留其餘項目。
// ui-polish(2026-11-11):拿掉「設定」大標題(底部導覽已標示所在分頁),比照
// 首頁只吃頂部安全區、內容從安全區下方 8 起;群組之間 16。
//
// 目標設定(GoalSettingsPage)、我的模板(TemplatesListPage)、偏好設定
// (PreferencesPage,另一工人換真身的契約 stub)皆為 zero-arg const 頁面,
// push 慣例照 dashboard_page.dart:64 附近(GoalSettingsPage)與
// start_workout_view.dart:54 附近(TemplatesListPage)的既有寫法。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/section_header.dart';
import '../auth/cloud_auth.dart';
import '../auth/session_controller.dart';
import '../goals/goal_settings_page.dart';
import '../workout/templates/templates_list_page.dart';
import 'about/about_page.dart';
import 'custom_exercises/custom_exercise_list_page.dart';
import 'preferences/preferences_page.dart';
import 'preferences/theme_preference.dart';
import 'preferences/weight_unit.dart';
import 'profile/profile_page.dart';
import 'tutorial/tutorial_page.dart';
import 'widgets/cloud_upload_status_tile.dart';
import 'widgets/import_retry_tile.dart';

/// 一組設定:小標題 + 一張群組卡片(內含 ListTile)。圖示一律單色
/// (onSurfaceVariant),層次由分組標題與卡片區隔,不靠每項各自的顏色。
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 標題上方不留白:群組間距由外層統一插 16,第一組才能貼齊頁頂 8。
        SectionHeader(
          title: title,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            0,
            AppSpacing.xs,
            AppSpacing.sm,
          ),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// 帶 chevron 的導頁項目。
class _NavTile extends StatelessWidget {
  const _NavTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListTile(
      leading: Icon(icon, color: muted),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Icon(Icons.chevron_right, color: muted),
      onTap: onTap,
    );
  }
}

/// 最常用的兩項偏好(重量單位、主題)直接放在設定主列表,行內 SegmentedButton
/// 選了就寫入。其餘偏好(休息秒數、1RM 公式、重置)在偏好設定子頁。
///
/// 寫入失敗處理同偏好設定子頁:各 controller 的 setXxx() 是「先寫 prefs 成功才更新
/// state」,失敗時 provider 值不變、SegmentedButton(完全受控,selected 每次 build
/// 從 provider 重算)自然顯示回舊選項;這裡只負責解除該項的 saving 並跳浮錯。
class _QuickPreferences extends ConsumerStatefulWidget {
  const _QuickPreferences();

  @override
  ConsumerState<_QuickPreferences> createState() => _QuickPreferencesState();
}

class _QuickPreferencesState extends ConsumerState<_QuickPreferences> {
  bool _savingWeightUnit = false;
  bool _savingTheme = false;

  static const _kWriteErrorMessage = '儲存失敗，請稍後再試';

  Future<void> _guardedWrite({
    required Future<void> Function() write,
    required void Function(bool saving) setSaving,
  }) async {
    setSaving(true);
    try {
      await write();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_kWriteErrorMessage)),
      );
    } finally {
      if (mounted) setSaving(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final weightUnit = ref.watch(weightUnitProvider);
    final themeMode = ref.watch(themeModeProvider);
    return Column(
      children: [
        _SegmentRow(
          icon: Icons.straighten,
          title: '重量單位',
          saving: _savingWeightUnit,
          child: SegmentedButton<WeightUnit>(
            key: const Key('weightUnitSegmentedButton'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: WeightUnit.kg, label: Text('公斤 (kg)')),
              ButtonSegment(value: WeightUnit.lb, label: Text('磅 (lb)')),
            ],
            selected: {weightUnit},
            onSelectionChanged: _savingWeightUnit
                ? null
                : (selection) => _guardedWrite(
                      write: () =>
                          ref.read(weightUnitControllerProvider.notifier).setUnit(selection.first),
                      setSaving: (saving) => setState(() => _savingWeightUnit = saving),
                    ),
          ),
        ),
        _SegmentRow(
          icon: Icons.brightness_6_outlined,
          title: '主題',
          saving: _savingTheme,
          child: SegmentedButton<ThemeMode>(
            key: const Key('themeModeSegmentedButton'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('跟隨系統')),
              ButtonSegment(value: ThemeMode.light, label: Text('淺色')),
              ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
            ],
            selected: {themeMode},
            onSelectionChanged: _savingTheme
                ? null
                : (selection) => _guardedWrite(
                      write: () => ref
                          .read(themeModeControllerProvider.notifier)
                          .setThemeMode(selection.first),
                      setSaving: (saving) => setState(() => _savingTheme = saving),
                    ),
          ),
        ),
      ],
    );
  }
}

/// 標題(單色圖示 + 文字,寫入中顯示小轉圈)在上、控制項全寬在下的一列。
class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    required this.icon,
    required this.title,
    required this.saving,
    required this.child,
  });

  final IconData icon;
  final String title;
  final bool saving;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.lg),
              Text(title, style: theme.textTheme.bodyLarge),
              if (saving) ...[
                const SizedBox(width: AppSpacing.sm),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
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

  /// 刪除帳號:兩段確認(App Store 5.1.1(v))→ 撤銷 Apple 授權(iOS,需重新
  /// 授權,取消則整個中止)→ 呼叫雲端刪除。成功後 session 清空,路由自動回登入頁;
  /// 失敗只提示,本機不動。
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
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('繼續'),
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
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('永久刪除'),
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
    final result = await ref.read(sessionControllerProvider.notifier).deleteAccount();
    if (navigator.mounted) navigator.pop();
    switch (result) {
      case DeleteAccountResult.cancelled:
        // 使用者在 Apple 重新授權時取消:整個刪除中止,不提示。
        break;
      case DeleteAccountResult.failed:
        messenger.showSnackBar(
          const SnackBar(content: Text('刪除帳號失敗,請確認網路後再試一次')),
        );
      case DeleteAccountResult.deleted:
        break;
      case DeleteAccountResult.deletedRevokeFailed:
        // 帳號已刪;Apple 授權沒撤銷成功的提示不在這裡彈:登出後設定頁隨 redirect 離場,
        // 疊在上面的 SnackBar/Dialog 會一起消失。deleteAccount 已把提示記進
        // postDeleteNoticeProvider,由登入頁以 AlertDialog 顯示(按「知道了」才關)。
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      // 不放頁名標題;只吃頂部安全區(狀態列),底部由分頁殼的導覽列負責。
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            // 單一 SliverToBoxAdapter(整段一次建置):項目數固定,且測試用
            // find.byKey 需要下方項目都在 Element tree 內。
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pageHorizontal,
                  AppSpacing.sm,
                  AppSpacing.pageHorizontal,
                  AppSpacing.xl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SettingsGroup(
                      title: '個人',
                      children: [
                        _NavTile(
                          key: const Key('settingsProfileEntry'),
                          icon: Icons.person_outline,
                          title: '個人資料',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => const ProfilePage()),
                          ),
                        ),
                        _NavTile(
                          key: const Key('settingsGoalEntry'),
                          icon: Icons.track_changes,
                          title: '目標設定',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => const GoalSettingsPage()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _SettingsGroup(
                      title: '訓練',
                      children: [
                        _NavTile(
                          key: const Key('settingsCustomExercisesEntry'),
                          icon: Icons.add_circle_outline,
                          title: '自定義動作',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const CustomExerciseListPage(),
                            ),
                          ),
                        ),
                        // 「我的模板」:設定入口保留於此(訓練開始頁另有入口,不在本頁範圍)。
                        _NavTile(
                          key: const Key('settingsTemplatesEntry'),
                          icon: Icons.description_outlined,
                          title: '我的模板',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => const TemplatesListPage()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _SettingsGroup(
                      title: '應用程式',
                      children: [
                        const _QuickPreferences(),
                        _NavTile(
                          key: const Key('settingsPreferencesEntry'),
                          icon: Icons.tune,
                          title: '偏好設定',
                          subtitle: '休息秒數、1RM 公式、重置',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => const PreferencesPage()),
                          ),
                        ),
                        _NavTile(
                          key: const Key('settingsTutorialEntry'),
                          icon: Icons.menu_book_outlined,
                          title: '使用教學',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => const TutorialPage()),
                          ),
                        ),
                        _NavTile(
                          key: const Key('settingsAboutEntry'),
                          icon: Icons.info_outline,
                          title: '關於',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => const AboutPage()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _SettingsGroup(
                      title: '帳號',
                      children: [
                        ListTile(
                          key: const Key('signOutButton'),
                          leading: Icon(Icons.logout, color: colors.onSurfaceVariant),
                          title: const Text('登出'),
                          onTap: () => _confirmSignOut(context, ref),
                        ),
                        // 只有雲端帳號才有「帳號」可刪;本機模式不顯示。破壞性動作
                        // 才用 error 色(圖示與文字)。
                        if (ref.watch(cloudAuthServiceProvider) != null)
                          ListTile(
                            key: const Key('deleteAccountButton'),
                            leading: Icon(Icons.delete_forever_outlined, color: colors.error),
                            title: Text('刪除帳號', style: TextStyle(color: colors.error)),
                            onTap: () => _confirmDeleteAccount(context, ref),
                          ),
                        // 僅在 CoreData 匯入永久失敗旗標為 true 時渲染,放群組尾。
                        const ImportRetryTile(),
                        // 雲端模式登入後本機舊資料上傳的狀態(idle 不渲染)。
                        const CloudUploadStatusTile(),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
