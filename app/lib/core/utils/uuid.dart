// 產生 UUID v4,給需要新建主鍵(Users / BodyWeights 等)的呼叫端共用。
// 刻意不引入 uuid 套件依賴——原本 features/onboarding/uuid.dart 與
// features/auth/session_controller.dart 各自抄了一份相同實作,收斂成這一份
// 共用工具(migration/coredata_importer_io.dart 的 `_generateUuidV4` 是禁區,
// 不搬,見該檔案開頭註解)。
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
