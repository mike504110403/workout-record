// 波 6 跨工人契約檔(大腦定,commit 在 feature/wave6 基底):偏好設定頁的
// 進入點。settings-core 工人(A)在設定頁骨架掛
// `Navigator.push(MaterialPageRoute(builder: (_) => const PreferencesPage()))`
// 入口;preferences 工人(B)把本 stub 換成真身(主題/預設休息秒數/1RM 公式/
// 重量單位四項,含 legacy 預填)。**類名與 zero-arg const 建構子是契約,
// 不得改。**
import 'package:flutter/material.dart';

class PreferencesPage extends StatelessWidget {
  const PreferencesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('偏好設定')),
      // WAVE6-STUB: B 工人換真身
      body: const Center(child: Text('偏好設定')),
    );
  }
}
