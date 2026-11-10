// PR 詳情頁的資料載入。依動作取全部 PR 歷史(`PersonalRecordRepository.
// fetchByExercise`,Drift 與 Supabase 兩邊皆已實作,Supabase 版走分頁 helper
// `selectAllPages`)。autoDispose + family:每次進入詳情頁都重新查詢。
//
// 不解析 userId:Drift 本機只有單一擁有者、Supabase 由 RLS 限定本人(見
// `supabase_personal_record_repository.dart` 類別文件),與 PR 列表用
// userId 篩選的結果等價。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/personal_record.dart';
import '../../../data/providers.dart';

final prDetailRecordsProvider = FutureProvider.autoDispose.family<List<PersonalRecord>, String>((
  ref,
  exerciseId,
) {
  return ref.read(personalRecordRepositoryProvider).fetchByExercise(exerciseId);
});
