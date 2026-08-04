// 共用的分區標題(minor 清理:先前 templates_list_page.dart 與
// template_picker_sheet.dart 各自複製了一份逐字相同的 `_SectionHeader`,
// 抽成一份共用)。
import 'package:flutter/material.dart';

class TemplateSectionHeader extends StatelessWidget {
  const TemplateSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}
