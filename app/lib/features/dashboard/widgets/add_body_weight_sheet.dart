// 記錄體重的 bottom sheet。對應 iOS 版
// `ios/WorkoutRecord/WorkoutRecord/Sources/Views/BodyWeight/AddBodyWeightSheet.swift`
// 的角色。
//
// 寫入 BodyWeightRepository 與畫面刷新(DashboardController.recordBodyWeight)
// 刻意在「彈窗還開著、還沒 pop」的時候就 await 完成,pop 動作放在寫入成功
// 之後——不是先 pop 再讓呼叫端(dashboard_page.dart)在背景繼續寫入。這樣
// widget test 只需要對「彈窗本身」pumpAndSettle 就能穩定等到寫入真的落地,
// 不會跟 showModalBottomSheet 的關閉轉場動畫的 Future resolve 時機打架
// (曾經吃過這個虧:寫入落在 pop 之後的續行程式碼裡,pumpAndSettle 偶爾會
// 在寫入真正完成前就判定「沒有排程中的 frame」而提前返回,造成間歇性
// flaky test)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dashboard_controller.dart';

class AddBodyWeightSheet extends ConsumerStatefulWidget {
  const AddBodyWeightSheet({super.key});

  @override
  ConsumerState<AddBodyWeightSheet> createState() => _AddBodyWeightSheetState();
}

class _AddBodyWeightSheetState extends ConsumerState<AddBodyWeightSheet> {
  final _controller = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? get _parsedWeight {
    final value = double.tryParse(_controller.text);
    if (value == null || value <= 0) return null;
    return value;
  }

  // 修復 M1:先前這裡寫入路徑沒有 try/catch/finally——recordBodyWeight
  // 拋錯時(例如 DB 寫入失敗、或 m3 修復後 userId 解析不到拋出的
  // StateError)_isSaving 會永遠卡在 true,欄位與按鈕全部 disable、也沒有
  // 任何錯誤提示,使用者只能重開 app。改成:寫入包 try,失敗時秀 SnackBar
  // 錯誤訊息;finally 裡確認 widget 還 mounted 才 setState 解除 loading
  // (避免 pop 之後畫面已卸載還呼叫 setState 噴 exception)。
  Future<void> _save() async {
    final weight = _parsedWeight;
    if (weight == null || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      await ref.read(dashboardControllerProvider.notifier).recordBodyWeight(weight);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('儲存失敗，請稍後再試')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('記錄體重', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            key: const Key('bodyWeightInputField'),
            controller: _controller,
            autofocus: true,
            enabled: !_isSaving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '體重 (kg)'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('saveBodyWeightButton'),
              onPressed: _parsedWeight != null && !_isSaving ? _save : null,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('儲存'),
            ),
          ),
        ],
      ),
    );
  }
}
