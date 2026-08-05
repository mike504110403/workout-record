// 體重紀錄列表（按 measuredAt 降序，對照 iOS `BodyWeightView.weightList` +
// `BodyWeightRow`）。每列可編輯（開表單帶原值）、可刪除（先跳確認對話框）。
import 'package:flutter/material.dart';

import '../../../../data/models/body_weight.dart';
import '../body_weight_format.dart';

class BodyWeightRecordList extends StatelessWidget {
  const BodyWeightRecordList({
    super.key,
    required this.entriesDesc,
    required this.onEdit,
    required this.onDelete,
  });

  /// 新到舊排序，直接依序渲染，不在這裡另外排序（排序責任在
  /// `BodyWeightRepository.fetchAll()` + controller，見
  /// body_weight_controller.dart 開頭註解）。
  final List<BodyWeight> entriesDesc;
  final ValueChanged<BodyWeight> onEdit;
  final ValueChanged<BodyWeight> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('歷史記錄', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        for (final entry in entriesDesc)
          _BodyWeightRow(
            entry: entry,
            onEdit: () => onEdit(entry),
            onDelete: () => _confirmDelete(context, entry),
          ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, BodyWeight entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('deleteBodyWeightDialog'),
        title: const Text('刪除這筆體重紀錄？'),
        content: Text('${formatBodyWeightDateTime(entry.measuredAt)} · ${formatBodyWeightKg(entry.weight)}'),
        actions: [
          TextButton(
            key: const Key('deleteBodyWeightCancelButton'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('deleteBodyWeightConfirmButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onDelete(entry);
    }
  }
}

class _BodyWeightRow extends StatelessWidget {
  const _BodyWeightRow({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  final BodyWeight entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('bodyWeightRow-${entry.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onEdit,
        title: Text(
          formatBodyWeightKg(entry.weight),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(formatBodyWeightDateTime(entry.measuredAt)),
            if (entry.note != null && entry.note!.isNotEmpty)
              Text(entry.note!, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: Key('editBodyWeightButton-${entry.id}'),
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
              tooltip: '編輯',
            ),
            IconButton(
              key: Key('deleteBodyWeightButton-${entry.id}'),
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: onDelete,
              tooltip: '刪除',
            ),
          ],
        ),
      ),
    );
  }
}
