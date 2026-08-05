// WAVE4-MERGE: merge 時由大腦換接真實作
import 'package:flutter/material.dart';

/// PR(個人記錄)列表頁 placeholder。接縫契約:zero-arg const
/// StatelessWidget,**自帶 Scaffold**(這裡是 `Navigator.push` 的推頁目的地,
/// 不是嵌在既有 Scaffold 底下的子頁)。
class PrListPage extends StatelessWidget {
  const PrListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('個人記錄')),
      body: const Center(child: Text('開發中')),
    );
  }
}
