# core/widgets

跨 feature 共用的 widget。樣式一律來自 `core/theme/`(`AppTheme`、`AppSpacing`、`AppRadius`、`AppSemanticColors`),
元件本身不寫死顏色或圓角。

| 元件 | 用途 |
| --- | --- |
| `AppCard` | 統一卡片(filled、圓角 16、padding 預設 16),可選 `onTap` |
| `SectionHeader` | 區塊標題列,右側可放 `trailing` 動作 |
| `MetricTile` | 大數字 + 小標籤,可選單位/趨勢,數字為 tabular figures |
| `MetricRow` | 多個 `MetricTile` 等分一列 |
| `EmptyState` | 空狀態:icon + 標題 + 說明 + 可選主按鈕 |
| `StatCard` | **@Deprecated**,請改用 `AppCard` + `MetricTile`;各頁遷移完成後移除 |

## 使用原則

- 間距只用 `AppSpacing`(4/8/12/16/24/32),頁面左右 `AppSpacing.pageHorizontal`(16)。
- 圓角只用 `AppRadius`(卡片 16、輸入/按鈕 12、chip 8、sheet 24)。
- 語意色用 `context.semanticColors`(success / warning / pr / 六個肌群色),不要寫死 `Colors.*`。
- 數字顯示用 `AppNumberStyles` 或 `TextStyle.tabular`,避免數值變動時抖動。
- 要新增共用元件請附 dartdoc 與淺/深主題的 widget test(`test/core/widgets/`)。
