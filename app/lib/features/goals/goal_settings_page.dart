// 目標設定頁。呈現波 5 唯二有消費者的欄位:週訓練次數目標(Dashboard 進度
// 條消費)與目標體重(Stats 體重頁的目標線消費,波 4 已接好)。六肌群容量
// 目標、restDayReminder 是 iOS 版的 write-only/無通知擺設,本波不做 UI
// (brief 明定)。
//
// 契約:同 pr_list_page.dart 的慣例——zero-arg const `StatelessWidget`(這裡
// 因為要管理表單輸入的本地狀態,實際上是 `ConsumerStatefulWidget`)、自帶
// Scaffold/AppBar,呼叫端直接 `Navigator.push` 到 `const GoalSettingsPage()`
// 即可,不需要外層再包殼、也不掛 route(本波不動 router.dart)。
//
// 表單型頁面,不做即時寫穿——`AddBodyWeightSheet` 那種立即輸入立即可存的
// 彈窗適合單一數值的快速記錄,這裡是「設定」語意,使用者可能想先看兩個欄位
// 一起調整過再一次確認存檔,所以明確給一顆「儲存」按鈕,不是每次 onChanged
// 就寫 DB。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/weight_format.dart';
import '../settings/preferences/weight_unit.dart';
import 'goal_settings_controller.dart';

/// 週訓練次數目標的值域(次/週)。
const _kMinWeeklyGoal = 0;
const _kMaxWeeklyGoal = 14;

/// 週訓練次數目標留空時的存檔值——語意是「未設定」,不是值域邊界(review
/// 打回 S5:先前跟 `_kMinWeeklyGoal` 混用同一個常數,巧合兩者數值都是 0,
/// 但意義不同——`_kMinWeeklyGoal` 是值域下界,這個是「使用者沒填」的預設
/// 存檔值,分開宣告避免以後值域下界改動時誤動到這裡)。
const _kUnsetWeeklyGoal = 0;

/// 目標體重的值域(儲存單位 kg;lb 模式下界限換算成 lb 後比對/提示)。
const _kMinTargetWeight = 20.0;
const _kMaxTargetWeight = 300.0;

class GoalSettingsPage extends ConsumerStatefulWidget {
  const GoalSettingsPage({super.key});

  @override
  ConsumerState<GoalSettingsPage> createState() => _GoalSettingsPageState();
}

class _GoalSettingsPageState extends ConsumerState<GoalSettingsPage> {
  final _weeklyGoalController = TextEditingController();
  final _targetWeightController = TextEditingController();

  /// 首次拿到 `GoalSettingsState`(不論有沒有既有目標)就把兩個欄位帶入表單
  /// 控制項一次——之後 provider 因為 `save()` 內的 `ref.invalidate` 之類的
  /// 原因重新 build() 也不要再覆寫使用者正在編輯的文字(不然使用者輸入到一
  /// 半、provider 剛好重新整理,輸入的文字會被蓋掉)。
  bool _prefilled = false;

  bool _isSaving = false;

  /// 存檔失敗時的錯誤訊息(固定文案,不把 exception 內容塞進 UI——對齊
  /// dashboard_page.dart / add_body_weight_sheet.dart 既有慣例)。
  static const _kSaveErrorMessage = '儲存失敗，請稍後再試';

  @override
  void dispose() {
    _weeklyGoalController.dispose();
    _targetWeightController.dispose();
    super.dispose();
  }

  void _prefillIfNeeded(GoalSettingsState state, WeightUnit unit) {
    if (_prefilled) return;
    _prefilled = true;
    _weeklyGoalController.text = state.weeklyWorkoutGoal > _kUnsetWeeklyGoal
        ? state.weeklyWorkoutGoal.toString()
        : '';
    // 儲存值恆 kg:帶入輸入框前依當前單位換算(lb 模式編輯既有目標時看到的是
    // lb 值)。kg 模式維持 `double.toString()` 原樣(no-op 回歸基準)。
    final stored = state.targetWeight;
    _targetWeightController.text = stored == null
        ? ''
        : (unit == WeightUnit.kg ? stored.toString() : formatWeightValue(stored, unit));
  }

  /// 解析週訓練次數目標。空字串代表「未設定」=[_kUnsetWeeklyGoal](對齊
  /// 規格「0=未設定」的語意,不是輸入錯誤);超出值域或非整數回傳 null
  /// 代表輸入不合法。
  int? get _parsedWeeklyGoal {
    final text = _weeklyGoalController.text.trim();
    if (text.isEmpty) return _kUnsetWeeklyGoal;
    final value = int.tryParse(text);
    if (value == null || value < _kMinWeeklyGoal || value > _kMaxWeeklyGoal) return null;
    return value;
  }

  /// 解析目標體重。空字串代表「未設定」=null(規格明定:留空存 null,不要
  /// 存 0——體重頁 targetWeight null 時不畫目標線)。`_TargetWeightParse.
  /// isValid` 為 false 代表輸入不合法(非數字或超出值域),與「合法的
  /// null」(留空)要分開表達,否則沒辦法區分「使用者故意清空」跟「使用者
  /// 打了無法解析的文字」這兩種情況。
  ///
  /// 輸入值視為當前單位 [unit];值域以 kg 界限換算成 [unit] 後比對(含邊界),
  /// 通過後 `displayToKg` 轉回 kg 入庫。
  _TargetWeightParse _parsedTargetWeight(WeightUnit unit) {
    final text = _targetWeightController.text.trim();
    if (text.isEmpty) return const _TargetWeightParse.valid(null);
    final value = double.tryParse(text);
    if (value == null) return const _TargetWeightParse.invalid();
    final kg = displayToKg(value, unit);
    // 邊界比對用 kg 側(輸入換回 kg 後)加微小容差:使用者輸入的是「界限換算後
    // 的 lb 值」(如 44.1),反向換算會有浮點誤差。
    const eps = 1e-9;
    if (kg < _kMinTargetWeight - eps || kg > _kMaxTargetWeight + eps) {
      return const _TargetWeightParse.invalid();
    }
    return _TargetWeightParse.valid(kg);
  }

  bool _canSave(WeightUnit unit) =>
      !_isSaving && _parsedWeeklyGoal != null && _parsedTargetWeight(unit).isValid;

  Future<void> _save() async {
    final unit = ref.read(weightUnitProvider);
    final weeklyGoal = _parsedWeeklyGoal;
    final targetWeight = _parsedTargetWeight(unit);
    if (weeklyGoal == null || !targetWeight.isValid || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      await ref.read(goalSettingsControllerProvider.notifier).save(
            weeklyWorkoutGoal: weeklyGoal,
            targetWeight: targetWeight.value,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_kSaveErrorMessage)),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(goalSettingsControllerProvider);
    final unit = ref.watch(weightUnitProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('目標設定')),
      body: asyncState.when(
        data: (state) {
          _prefillIfNeeded(state, unit);
          return _buildForm(context, unit);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        // 查詢失敗(初次載入既有目標時)同 dashboard_page.dart 的既有慣例:
        // 補一顆重試按鈕 invalidate provider,不讓使用者卡死在死路。
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('載入失敗，請稍後再試'),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('goalSettingsErrorRetryButton'),
                onPressed: () => ref.invalidate(goalSettingsControllerProvider),
                child: const Text('重試'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, WeightUnit unit) {
    final weeklyGoalInvalid = _parsedWeeklyGoal == null;
    final targetWeightInvalid = !_parsedTargetWeight(unit).isValid;
    // 值域提示的界限值:kg 模式為 20/300(與改造前逐字相同);lb 模式為換算後
    // 並取整的界限(輸入下界以 ceil、上界以 floor 取整,提示顯示的整數界限必
    // 然通過驗證)。
    final minShown = _shownBound(_kMinTargetWeight, unit, up: true);
    final maxShown = _shownBound(_kMaxTargetWeight, unit, up: false);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('週訓練次數目標', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            key: const Key('weeklyWorkoutGoalField'),
            controller: _weeklyGoalController,
            enabled: !_isSaving,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '每週次數(0-14)',
              errorText: weeklyGoalInvalid ? '請輸入 0-14 的整數' : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),
          Text('目標體重', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            key: const Key('targetWeightField'),
            controller: _targetWeightController,
            enabled: !_isSaving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '目標體重 (${unitSuffix(unit)}),留空代表未設定',
              errorText: targetWeightInvalid ? '請輸入 $minShown-$maxShown 的體重,或留空' : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('saveGoalSettingsButton'),
              onPressed: _canSave(unit) ? _save : null,
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

/// 值域界限(kg)換算成 [unit] 後的整數提示值。[up] 為 true 取 ceil(下界,
/// 避免提示的下界落在合法範圍之外),否則取 floor(上界)。kg 模式原值即整數。
int _shownBound(double kgBound, WeightUnit unit, {required bool up}) {
  final v = kgToDisplay(kgBound, unit);
  return (up ? v.ceil() : v.floor());
}

/// 目標體重解析結果——區分「合法(含合法的留空=null)」與「不合法」,單純用
/// `double?` 沒辦法表達這個差異(null 同時可能代表「合法的未設定」或「打了
/// 無法解析的文字」)。
class _TargetWeightParse {
  const _TargetWeightParse.valid(this.value) : isValid = true;
  const _TargetWeightParse.invalid()
      : isValid = false,
        value = null;

  final bool isValid;
  final double? value;
}
