// App 顯示名稱統一為「Work It Out」(與 lib/app.dart title、Android label、
// iOS CFBundleDisplayName 一致)。掃 lib/ 下所有 .dart 的非註解行,字串字面值
// 不得再以舊寫法當 App 名:WorkoutRecord、WorkItOut、「歡迎使用健身記錄」、
// 單獨的「健身記錄」。識別字(WorkItOutApp 類別名、Bundle ID
// com.mikelin.workitout)不在字串字面值內或不含上述字樣,不受影響;註解中
// 引用 iOS 路徑(ios/WorkoutRecord/...)也不算顯示文字;舊 CoreData 檔名
// `WorkoutRecord.sqlite` 是檔案識別字,同樣排除。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lib/ 字串字面值沒有舊 App 名(WorkoutRecord / WorkItOut / 健身記錄)', () {
    final literal = RegExp(
      r'''(['"])[^'"\n]*(WorkoutRecord(?!\.sqlite)|WorkItOut|歡迎使用\s*健身記錄)[^'"\n]*\1|(['"])健身記錄\3''',
    );
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trimLeft();
        if (trimmed.startsWith('//')) continue;
        if (literal.hasMatch(lines[i])) {
          offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('lib/app.dart 的 App title 是 Work It Out', () {
    expect(File('lib/app.dart').readAsStringSync(), contains("title: 'Work It Out'"));
  });
}
