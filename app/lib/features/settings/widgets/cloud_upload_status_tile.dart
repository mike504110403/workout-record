// 登入後「本機舊資料 → 雲端」一次性上傳的使用者可見狀態(設定頁列表尾,
// ImportRetryTile 旁)。idle(沒在上傳、或不需要上傳)不渲染;上傳中顯示進度;
// 成功顯示筆數;失敗顯示錯誤與「重試上傳」按鈕(下次啟動也會自動重試)。
// 狀態來源與觸發見 features/cloud_upload/cloud_upload_controller.dart。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cloud_upload/cloud_upload_controller.dart';

class CloudUploadStatusTile extends ConsumerWidget {
  const CloudUploadStatusTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(cloudUploadControllerProvider);
    switch (status.phase) {
      case CloudUploadPhase.idle:
        return const SizedBox.shrink();
      case CloudUploadPhase.uploading:
        return const ListTile(
          key: Key('cloudUploadUploading'),
          leading: Icon(Icons.cloud_upload_outlined),
          title: Text('正在把舊資料上傳到雲端'),
          subtitle: Text('完成前請保持 App 開啟'),
          trailing: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case CloudUploadPhase.succeeded:
        return ListTile(
          key: const Key('cloudUploadSucceeded'),
          leading: const Icon(Icons.cloud_done_outlined, color: Colors.green),
          title: const Text('舊資料已上傳到雲端'),
          subtitle: Text('共 ${status.uploadedRows} 筆'),
        );
      case CloudUploadPhase.failed:
        return ListTile(
          key: const Key('cloudUploadFailed'),
          leading: const Icon(Icons.cloud_off_outlined, color: Colors.orange),
          title: const Text('舊資料上傳雲端失敗'),
          subtitle: Text(
            status.errorMessage ?? '未知錯誤',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: TextButton(
            key: const Key('cloudUploadRetryButton'),
            onPressed: () => ref.read(cloudUploadControllerProvider.notifier).runIfNeeded(),
            child: const Text('重試上傳'),
          ),
        );
    }
  }
}
