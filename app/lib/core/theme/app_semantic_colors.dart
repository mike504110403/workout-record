import 'package:flutter/material.dart';

/// 語意色票:Material [ColorScheme] 沒有的「訓練語意」顏色。
///
/// 透過 `Theme.of(context).extension<AppSemanticColors>()` 取得,
/// 或用便利的 `context.semanticColors`(見 [AppSemanticColorsContext])。
/// 淺色/深色各有一套([AppSemanticColors.light]、[AppSemanticColors.dark]),
/// 由 [AppTheme] 注入。
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.warning,
    required this.pr,
    required this.muscleChest,
    required this.muscleBack,
    required this.muscleLegs,
    required this.muscleShoulders,
    required this.muscleArms,
    required this.muscleCore,
  });

  /// 成功/達標。
  final Color success;

  /// 警告/接近上限。
  final Color warning;

  /// 個人紀錄(PR),琥珀色。
  final Color pr;

  final Color muscleChest;
  final Color muscleBack;
  final Color muscleLegs;
  final Color muscleShoulders;
  final Color muscleArms;
  final Color muscleCore;

  /// 淺色主題色票。
  static const AppSemanticColors light = AppSemanticColors(
    success: Color(0xFF2E7D32),
    warning: Color(0xFFED6C02),
    pr: Color(0xFFF59E0B),
    muscleChest: Color(0xFFD94452),
    muscleBack: Color(0xFF2F6FDB),
    muscleLegs: Color(0xFF2E9E6B),
    muscleShoulders: Color(0xFFE07B1F),
    muscleArms: Color(0xFF8E52D1),
    muscleCore: Color(0xFF0F9DAE),
  );

  /// 深色主題色票(亮度提高以維持對比)。
  static const AppSemanticColors dark = AppSemanticColors(
    success: Color(0xFF66BB6A),
    warning: Color(0xFFFFA726),
    pr: Color(0xFFFBBF24),
    muscleChest: Color(0xFFFF7A86),
    muscleBack: Color(0xFF6FA3FF),
    muscleLegs: Color(0xFF5FD39A),
    muscleShoulders: Color(0xFFFFA24D),
    muscleArms: Color(0xFFBB86F0),
    muscleCore: Color(0xFF4DD0E1),
  );

  /// 六個肌群色,順序:胸、背、腿、肩、手臂、核心。
  List<Color> get muscleColors => [
    muscleChest,
    muscleBack,
    muscleLegs,
    muscleShoulders,
    muscleArms,
    muscleCore,
  ];

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? pr,
    Color? muscleChest,
    Color? muscleBack,
    Color? muscleLegs,
    Color? muscleShoulders,
    Color? muscleArms,
    Color? muscleCore,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      pr: pr ?? this.pr,
      muscleChest: muscleChest ?? this.muscleChest,
      muscleBack: muscleBack ?? this.muscleBack,
      muscleLegs: muscleLegs ?? this.muscleLegs,
      muscleShoulders: muscleShoulders ?? this.muscleShoulders,
      muscleArms: muscleArms ?? this.muscleArms,
      muscleCore: muscleCore ?? this.muscleCore,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      pr: Color.lerp(pr, other.pr, t)!,
      muscleChest: Color.lerp(muscleChest, other.muscleChest, t)!,
      muscleBack: Color.lerp(muscleBack, other.muscleBack, t)!,
      muscleLegs: Color.lerp(muscleLegs, other.muscleLegs, t)!,
      muscleShoulders: Color.lerp(muscleShoulders, other.muscleShoulders, t)!,
      muscleArms: Color.lerp(muscleArms, other.muscleArms, t)!,
      muscleCore: Color.lerp(muscleCore, other.muscleCore, t)!,
    );
  }
}

/// `BuildContext` 便利存取:`context.semanticColors.pr`。
///
/// 若主題未註冊 [AppSemanticColors](例如測試用裸 `ThemeData`),
/// 依亮度回退到 [AppSemanticColors.light]/[AppSemanticColors.dark]。
extension AppSemanticColorsContext on BuildContext {
  AppSemanticColors get semanticColors {
    final theme = Theme.of(this);
    return theme.extension<AppSemanticColors>() ??
        (theme.brightness == Brightness.dark
            ? AppSemanticColors.dark
            : AppSemanticColors.light);
  }
}
