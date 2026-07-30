// 產生 UUID v4,給 Onboarding 完成時新建的 Users / BodyWeights 資料列當主鍵。
// 刻意不引入 uuid 套件依賴,寫法對齊
// app/lib/data/migration/coredata_importer_io.dart 內部的 `_generateUuidV4`。
import 'dart:math';

final _uuidRandom = Random.secure();

String generateUuidV4() {
  final bytes = List<int>.generate(16, (_) => _uuidRandom.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xxxxxx
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20, 32)}';
}
