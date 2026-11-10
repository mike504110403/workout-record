// 1RM 公式說明頁:文案照搬 iOS `Views/Settings/SettingsView.swift` 的
// `FormulaExplanationView`(Epley / Brzycki / Lander 三條公式 + 適用情境)。
import 'package:flutter/material.dart';

class FormulaExplanationPage extends StatelessWidget {
  const FormulaExplanationPage({super.key});

  static const _formulas = [
    ('Epley 公式', '1RM = 重量 × (1 + 次數 / 30)', '最常用的公式，適合大多數情況。'),
    ('Brzycki 公式', '1RM = 重量 × (36 / (37 - 次數))', '較保守的估算，適合次數較少的情況。'),
    ('Lander 公式', '1RM = 重量 × (100 / (101.3 - 2.67123 × 次數))', '適合高次數的訓練估算。'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('1RM 公式說明')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final f in _formulas)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.$1,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      f.$2,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(f.$3, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
