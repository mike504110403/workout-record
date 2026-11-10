// 離線草稿與快取在 SharedPreferences 的 key 前綴(清本機資料時一次清掉)。
import 'offline_cached_exercise_repository.dart';
import 'offline_cached_template_repository.dart';
import 'offline_cached_user_repository.dart';
import 'offline_draft_workout_repository.dart';

const kOfflinePrefsKeyPrefixes = <String>[
  OfflineDraftWorkoutRepository.keyPrefix,
  OfflineCachedUserRepository.keyPrefix,
  OfflineCachedExerciseRepository.keyPrefix,
  OfflineCachedTemplateRepository.keyPrefix,
];
