// 個人資料頁:姓名/性別/身高三欄,存 SharedPreferences。契約:zero-arg
// const 建構子、自帶 Scaffold/AppBar,呼叫端 `Navigator.push` 即可(同
// goal_settings_page.dart 慣例)。**不做**目標體重/週目標(單一真源是
// GoalSettingsPage,brief 明定)、email/年齡(iOS 無 UI 寫入路徑)。
//
// 表單型頁面,不即時寫穿——同 goal_settings_page.dart 理由:使用者可能想
// 三欄一起調整過再一次確認存檔,給明確的「儲存」按鈕。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import 'profile_controller.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _nameController = TextEditingController();
  final _heightController = TextEditingController();

  /// 只在第一次拿到 [ProfileFormState] 時把欄位帶入表單控制項——之後
  /// `save()` 內的 `ref.invalidateSelf()` 造成的重新 build() 不再覆寫使用者
  /// 正在編輯的文字(同 goal_settings_page.dart `_prefillIfNeeded` 慣例)。
  bool _prefilled = false;

  String _gender = kProfileDefaultGender;
  bool _isSaving = false;

  static const _kSaveErrorMessage = '儲存失敗，請稍後再試';

  @override
  void dispose() {
    _nameController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _prefillIfNeeded(ProfileFormState state) {
    if (_prefilled) return;
    _prefilled = true;
    _nameController.text = state.name;
    _gender = state.gender;
    _heightController.text = state.heightCm?.toString() ?? '';
  }

  /// 身高:留空代表未設定(存檔時清除既有值,見
  /// `ProfilePrefsWriter.write`);有輸入但無法解析成數字視為不合法,擋存檔。
  _HeightParse get _parsedHeight {
    final text = _heightController.text.trim();
    if (text.isEmpty) return const _HeightParse.valid(null);
    final value = double.tryParse(text);
    if (value == null) return const _HeightParse.invalid();
    return _HeightParse.valid(value);
  }

  bool get _canSave => !_isSaving && _parsedHeight.isValid;

  Future<void> _save() async {
    final height = _parsedHeight;
    if (!height.isValid || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      await ref.read(profileControllerProvider.notifier).save(
            name: _nameController.text.trim(),
            gender: _gender,
            heightCm: height.value,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('個人資料已更新')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(_kSaveErrorMessage)));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileControllerProvider);
    _prefillIfNeeded(state);
    final heightInvalid = !_parsedHeight.isValid;

    return Scaffold(
      appBar: AppBar(title: const Text('個人資料')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('姓名', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const Key('profileNameField'),
              controller: _nameController,
              enabled: !_isSaving,
              decoration: const InputDecoration(hintText: '請輸入姓名(選填)'),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('性別', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<String>(
              key: const Key('profileGenderToggle'),
              segments: [
                for (final option in kProfileGenderOptions)
                  ButtonSegment(value: option, label: Text(option)),
              ],
              selected: {_gender},
              onSelectionChanged: _isSaving
                  ? null
                  : (selection) => setState(() => _gender = selection.first),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('身高', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('profileHeightField'),
                    controller: _heightController,
                    enabled: !_isSaving,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText: '請輸入身高(選填)',
                      errorText: heightInvalid ? '請輸入數字,或留空' : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                const Text('cm'),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('saveProfileButton'),
                onPressed: _canSave ? _save : null,
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
      ),
    );
  }
}

/// 身高解析結果——區分「合法(含合法的留空=null)」與「不合法」,單純用
/// `double?` 沒辦法表達這個差異(同 goal_settings_page.dart
/// `_TargetWeightParse` 慣例)。
class _HeightParse {
  const _HeightParse.valid(this.value) : isValid = true;
  const _HeightParse.invalid()
      : isValid = false,
        value = null;

  final bool isValid;
  final double? value;
}
