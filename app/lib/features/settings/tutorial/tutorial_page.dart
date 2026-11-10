// 使用教學頁。內容與章節結構參考 iOS `Views/Tutorial/TutorialView.swift`
// (快速開始 / 主要功能 / 進階功能 / 實用技巧 / 常見問題 / 底部說明),
// 文案依 Flutter 版現況調整的句子見各常數旁註解(與 iOS 的差異)。
//
// 2026-11 改版:Onboarding 縮成「基本資訊 + 目標」兩步、不再介紹功能,
// 功能導覽由本頁獨立負責;版面改為「章節標題 + 單張 AppCard」,圖示統一
// 用 colorScheme.primary(不再每章一個寫死顏色)。
//
// 契約:zero-arg const 建構子、自帶 Scaffold/AppBar(同設定子頁慣例)。
// 入口:設定頁「使用教學」(settingsTutorialEntry)與關於頁「新手教學」
// (aboutTutorialTile),皆為 Navigator.push。
import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_card.dart';

class TutorialPage extends StatelessWidget {
  const TutorialPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('使用教學')),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageHorizontal,
          vertical: AppSpacing.lg,
        ),
        children: [
          Text(
            '歡迎使用 Work It Out',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '完整的健身訓練記錄工具',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xl),
          const _Section(
            key: Key('tutorialSectionQuickStart'),
            title: '快速開始',
            icon: Icons.local_fire_department,
            children: [
              // iOS:「點擊首頁的「開始訓練」按鈕，選擇訓練模板或自由訓練」。
              // Flutter 的入口在「訓練」分頁,按鈕為「開始自由訓練」「從模板開始」。
              _Step(
                number: 1,
                title: '開始訓練',
                description: '前往「訓練」分頁，選擇「開始自由訓練」或「從模板開始」',
              ),
              _Step(
                number: 2,
                title: '新增動作',
                description: '點擊「新增動作」，從動作庫選擇您要訓練的項目',
              ),
              _Step(
                number: 3,
                title: '記錄組數',
                description: '點擊「新增組數」，輸入重量和次數，系統會自動計算訓練容量',
              ),
              // iOS:「結束訓練」;Flutter 的按鈕文字為「完成訓練」。
              _Step(
                number: 4,
                title: '完成訓練',
                description: '完成所有組數後，點擊「完成訓練」保存記錄',
              ),
            ],
          ),
          const _Section(
            key: Key('tutorialSectionFeatures'),
            title: '主要功能',
            icon: Icons.star,
            children: [
              _InfoRow(
                icon: Icons.home,
                title: '首頁',
                description: '查看訓練統計、今日訓練進度和快速開始訓練',
              ),
              _InfoRow(
                icon: Icons.fitness_center,
                title: '訓練',
                description: '記錄訓練過程，支援自由訓練和模板訓練',
              ),
              // iOS:「查看訓練容量趨勢、肌群分析和個人記錄」。Flutter 的數據頁
              // 分為體重 / 訓練 / 三項三個分頁,沒有獨立的肌群分析。
              _InfoRow(
                icon: Icons.show_chart,
                title: '數據',
                description: '查看體重變化、訓練容量趨勢和個人記錄',
              ),
              _InfoRow(
                icon: Icons.calendar_today,
                title: '歷史',
                description: '查看過往訓練記錄，支援日曆和列表視圖',
              ),
              _InfoRow(
                icon: Icons.settings,
                title: '設定',
                description: '管理個人資料、目標設定和 App 偏好',
              ),
            ],
          ),
          const _Section(
            key: Key('tutorialSectionAdvanced'),
            title: '進階功能',
            icon: Icons.auto_awesome,
            children: [
              // iOS:「設定每週訓練次數和肌群容量目標…」。Flutter 目標設定只有
              // 週訓練次數與目標體重(肌群容量目標無 UI)。
              _InfoRow(
                icon: Icons.track_changes,
                title: '目標設定',
                description: '設定每週訓練次數和目標體重，App 會追蹤您的進度並提供鼓勵',
              ),
              _InfoRow(
                icon: Icons.description_outlined,
                title: '訓練模板',
                description: '建立自己的訓練模板，下次訓練時可以快速開始',
              ),
              // iOS:「內建 67 個常用動作」;Flutter 種子資料為 66 筆。
              _InfoRow(
                icon: Icons.list,
                title: '動作庫',
                description: '內建 66 個常用動作，也可以新增自定義動作',
              ),
              _InfoRow(
                icon: Icons.monitor_weight,
                title: '體重追蹤',
                description: '記錄體重變化，配合訓練數據追蹤身體組成',
              ),
              _InfoRow(
                icon: Icons.emoji_events,
                title: '個人記錄',
                description: '自動追蹤您的 1RM（單次最大重量）進步情況',
              ),
            ],
          ),
          const _Section(
            key: Key('tutorialSectionTips'),
            title: '實用技巧',
            icon: Icons.lightbulb,
            children: [
              _InfoRow(
                icon: Icons.bolt,
                title: '快速輸入',
                description: '訓練時可以參考上一組的重量和次數，快速完成輸入',
              ),
              // iOS:「記錄每組後會自動開始休息計時」。Flutter 暖身組不啟動,
              // 且新增組數時可關閉自動計時。
              _InfoRow(
                icon: Icons.timer,
                title: '休息計時',
                description: '記錄每組後會自動開始休息計時（暖身組除外），確保充分恢復',
              ),
              _InfoRow(
                icon: Icons.bar_chart,
                title: '訓練容量',
                description: '訓練容量 = 重量 × 次數，是衡量訓練量的重要指標',
              ),
              _InfoRow(
                icon: Icons.search,
                title: '智能搜尋',
                description: '動作庫支援中英文搜尋，還能根據肌群篩選',
              ),
            ],
          ),
          const _Section(
            key: Key('tutorialSectionFaq'),
            title: '常見問題',
            icon: Icons.help,
            asCard: false,
            children: [
              // iOS:「向左滑動組數記錄，可以選擇編輯或刪除」。Flutter 的組數
              // 列右側直接提供編輯與刪除按鈕,不是滑動操作。
              _FaqCard(
                question: '如何修改已記錄的組數？',
                answer: '在訓練頁面，點擊組數右側的鉛筆圖示可以編輯，點擊「×」可以刪除',
              ),
              _FaqCard(
                question: '如何查看進步情況？',
                answer: '前往「數據」頁面，可以查看訓練容量趨勢和個人記錄',
              ),
            ],
          ),
          Center(
            child: Text('需要更多協助？', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: AppSpacing.sm),
          // iOS:「歡迎透過 App Store 評價或聯絡我們」。Flutter 版改指向
          // 「設定 > 關於」的聯絡我們。
          Text(
            '如有任何問題或建議，歡迎至「設定 > 關於」聯絡我們',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

/// 章節:圖示 + 標題列,下方內容預設包在單張 [AppCard] 內(列與列之間
/// [AppSpacing.lg] 間距);[asCard] 為 false 時各 child 自帶卡片(FAQ)。
class _Section extends StatelessWidget {
  const _Section({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.asCard = true,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool asCard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gap = asCard ? AppSpacing.lg : AppSpacing.sm;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          children[i],
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary, size: 22),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          if (asCard) SizedBox(width: double.infinity, child: AppCard(child: body)) else body,
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.description});

  final int number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: theme.colorScheme.primary,
          child: Text(
            '$number',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
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

/// 圖示 + 標題 + 說明的一列(主要功能 / 進階功能 / 實用技巧共用)。
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.title, required this.description});

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 28, child: Icon(icon, color: theme.colorScheme.primary, size: 22)),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
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

/// 可展開的問答卡(對照 iOS `FAQCard`:點問題展開/收合答案)。
class _FaqCard extends StatefulWidget {
  const _FaqCard({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  State<_FaqCard> createState() => _FaqCardState();
}

class _FaqCardState extends State<_FaqCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: Key('tutorialFaq-${widget.question}'),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.question,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 20),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
              child: Text(
                widget.answer,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}
