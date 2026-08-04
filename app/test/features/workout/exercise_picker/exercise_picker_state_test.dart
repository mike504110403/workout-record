// ExercisePickerState 純 Dart unit test:即時搜尋的比對範圍(中文名/英文名/
// 主要肌群顯示名稱)與最愛置頂排序,獨立於 widget 樹之外直接斷言計算邏輯。
// 參照值全部手算,不抄 exercise_picker_controller.dart 裡的同一份公式。

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/data/models/exercise.dart';
import 'package:workout_record/features/workout/exercise_picker/exercise_picker_controller.dart';

Exercise _buildExercise({
  required String id,
  required String name,
  String? nameEn,
  PrimaryMuscleGroup? primaryMuscleGroup,
  String categoryId = 'category-1',
}) {
  final now = DateTime(2026, 1, 1);
  return Exercise(
    id: id,
    name: name,
    nameEn: nameEn,
    categoryId: categoryId,
    type: ExerciseType.freeWeight,
    primaryMuscleGroup: primaryMuscleGroup,
    isSystem: true,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  final benchPress = _buildExercise(
    id: 'e1',
    name: '槓鈴臥推',
    nameEn: 'Barbell Bench Press',
    primaryMuscleGroup: PrimaryMuscleGroup.chest,
  );
  final squat = _buildExercise(
    id: 'e2',
    name: '深蹲',
    nameEn: 'Squat',
    primaryMuscleGroup: PrimaryMuscleGroup.legs,
  );
  final facePull = _buildExercise(
    id: 'e3',
    name: '臉拉',
    nameEn: 'Face Pull',
    primaryMuscleGroup: PrimaryMuscleGroup.shoulders,
  );
  final plank = _buildExercise(id: 'e4', name: '棒式', nameEn: 'Plank', primaryMuscleGroup: PrimaryMuscleGroup.core);

  group('searchResults', () {
    test('中文名關鍵字比對:「臥推」只命中槓鈴臥推', () {
      final state = ExercisePickerState(
        allExercises: [benchPress, squat, facePull, plank],
        favoriteIds: const {},
        searchQuery: '臥推',
      );

      expect(state.searchResults.map((e) => e.id), ['e1']);
    });

    test('英文名關鍵字比對(不分大小寫):「squat」命中深蹲', () {
      final state = ExercisePickerState(
        allExercises: [benchPress, squat, facePull, plank],
        favoriteIds: const {},
        searchQuery: 'squat',
      );

      expect(state.searchResults.map((e) => e.id), ['e2']);
    });

    test('主要肌群顯示名稱關鍵字比對:「肩」命中臉拉(primaryMuscleGroup=shoulders)', () {
      final state = ExercisePickerState(
        allExercises: [benchPress, squat, facePull, plank],
        favoriteIds: const {},
        searchQuery: '肩',
      );

      expect(state.searchResults.map((e) => e.id), ['e3']);
    });

    test('查無關鍵字回傳空清單', () {
      final state = ExercisePickerState(
        allExercises: [benchPress, squat, facePull, plank],
        favoriteIds: const {},
        searchQuery: '不存在的關鍵字',
      );

      expect(state.searchResults, isEmpty);
    });

    test('空白查詢字串視為未搜尋,回傳空清單(由 isSearching 分流,不是「全部」)', () {
      final state = ExercisePickerState(
        allExercises: [benchPress, squat],
        favoriteIds: const {},
        searchQuery: '   ',
      );

      expect(state.isSearching, isFalse);
      expect(state.searchResults, isEmpty);
    });

    test('搜尋結果套用最愛置頂排序:命中兩筆時,最愛的排前面(即使字典序在後)', () {
      // 深蹲、槓鈴臥推都含有 primaryMuscleGroup displayName,不會同時命中同一
      // 個關鍵字,這裡直接手造兩筆都會命中同一查詢字串的 fixture。
      //
      // code review r2 minor S5:fixture 選的最愛(legCurl/腿彎舉)恰好字典序
      // 本來就排最前(彎 U+5F4E < 推 U+63A8),就算 `visibleExercises`/
      // `searchResults` 完全不做「最愛置頂」、只單純照名稱排序,結果也會
      // 剛好一樣,測試守不住置頂邏輯本身。改成最愛選字典序本來會排在後面
      // 的那筆(legPress/腿推機),斷言它被置頂排到前面——這樣把置頂邏輯拿掉
      // 才會讓這條測試真的變紅。
      final legPress = _buildExercise(
        id: 'e5',
        name: '腿推機',
        nameEn: 'Leg Press',
        primaryMuscleGroup: PrimaryMuscleGroup.legs,
      );
      final legCurl = _buildExercise(
        id: 'e6',
        name: '腿彎舉',
        nameEn: 'Leg Curl',
        primaryMuscleGroup: PrimaryMuscleGroup.legs,
      );
      final state = ExercisePickerState(
        allExercises: [legPress, legCurl],
        favoriteIds: const {'e5'},
        searchQuery: '腿',
      );

      expect(state.searchResults.map((e) => e.id), ['e5', 'e6']);
    });
  });

  group('visibleExercises', () {
    test('未選分類時等同 allExercises,套用最愛置頂 + 名稱排序', () {
      final state = ExercisePickerState(
        allExercises: [squat, benchPress, plank],
        favoriteIds: const {'e1'}, // 槓鈴臥推最愛
      );

      // 手算參照:槓鈴臥推置頂,其餘按名稱字典序(深蹲 vs 棒式:比較
      // Unicode code point,深(U+6DF1)> 棒(U+68D2),所以棒式在前)。
      expect(state.visibleExercises.map((e) => e.id), ['e1', 'e4', 'e2']);
    });

    test('選了分類時改用 categoryExercises,同樣套用最愛置頂排序(即使字典序在後)', () {
      // code review r2 minor S5:原本最愛選棒式(e4),字典序本來就排在深蹲
      // (e2)前面(棒 U+68D2 < 深 U+6DF1),拿掉置頂邏輯結果也一樣,測試守不住
      // 置頂本身。改成最愛選字典序本來會排在後面的深蹲(e2),斷言它被置頂
      // 排到前面。
      final state = ExercisePickerState(
        allExercises: [squat, benchPress, plank],
        favoriteIds: const {'e2'},
        selectedCategoryId: 'legs-category',
        categoryExercises: [squat, plank],
      );

      expect(state.visibleExercises.map((e) => e.id), ['e2', 'e4']);
    });
  });

  group('copyWith 哨兵值', () {
    test('不傳 selectedCategoryId/customExerciseError 時維持原值(不會被誤清成 null)', () {
      const state = ExercisePickerState(
        allExercises: [],
        favoriteIds: {},
        selectedCategoryId: 'cat-1',
        customExerciseError: '舊錯誤',
      );

      final copied = state.copyWith(searchQuery: 'x');

      expect(copied.selectedCategoryId, 'cat-1');
      expect(copied.customExerciseError, '舊錯誤');
    });

    test('明確傳 null 時真的清掉該欄位', () {
      const state = ExercisePickerState(
        allExercises: [],
        favoriteIds: {},
        selectedCategoryId: 'cat-1',
        customExerciseError: '舊錯誤',
      );

      final copied = state.copyWith(selectedCategoryId: null, customExerciseError: null);

      expect(copied.selectedCategoryId, isNull);
      expect(copied.customExerciseError, isNull);
    });
  });
}
