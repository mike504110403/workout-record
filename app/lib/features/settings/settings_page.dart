import 'package:flutter/material.dart';

import 'widgets/import_retry_tile.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: Column(
        children: [
          const Expanded(
            child: Center(
              child: Text('設定', style: TextStyle(fontSize: 24)),
            ),
          ),
          const ImportRetryTile(), // 僅在 CoreData 匯入永久失敗旗標為 true 時渲染。
        ],
      ),
    );
  }
}
