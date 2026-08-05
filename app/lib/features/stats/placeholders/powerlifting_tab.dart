// WAVE4-MERGE: merge 時由大腦換接真實作
import 'package:flutter/material.dart';

/// 三項子頁 placeholder(波 4 由另一位平行工人實作真正內容)。接縫契約:
/// zero-arg const StatelessWidget,不帶 Scaffold(嵌在 StatsPage 的
/// IndexedStack 內,由外層 Scaffold 提供 AppBar)。
class PowerliftingTab extends StatelessWidget {
  const PowerliftingTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('開發中'));
  }
}
