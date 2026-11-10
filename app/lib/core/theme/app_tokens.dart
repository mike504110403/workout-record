import 'package:flutter/widgets.dart';

/// 間距 token(4pt 網格)。
///
/// 新程式碼一律用這裡的值,不要再寫散落的 magic number。
/// 頁面左右留白統一用 [pageHorizontal]。
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// 頁面左右留白。
  static const double pageHorizontal = 16;

  /// 頁面左右留白的 [EdgeInsets] 版本。
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(
    horizontal: pageHorizontal,
  );
}

/// 圓角 token。
class AppRadius {
  const AppRadius._();

  /// 卡片。
  static const double card = 16;

  /// 輸入框、按鈕。
  static const double control = 12;

  /// Chip。
  static const double chip = 8;

  /// Bottom sheet 頂部。
  static const double sheet = 24;

  static const BorderRadius cardRadius = BorderRadius.all(
    Radius.circular(card),
  );
  static const BorderRadius controlRadius = BorderRadius.all(
    Radius.circular(control),
  );
  static const BorderRadius chipRadius = BorderRadius.all(
    Radius.circular(chip),
  );
  static const BorderRadius sheetRadius = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
}

/// 元件尺寸 token。
class AppSizes {
  const AppSizes._();

  /// 按鈕最小高度(符合觸控目標建議)。
  static const double buttonHeight = 48;
}
