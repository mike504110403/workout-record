// 選動作器用的分類展示清單。
//
// 對照 iOS `MockData.swift` 的 `categories` 陣列:胸/背/腿/肩/手臂/核心 六個
// 分類,id 用寫死的固定 UUID(00000000-0000-0000-0000-000000000001~6)。
// Flutter 版同一組常數已經定義在 `data/db/seed_data.dart` 的
// `SeedCategoryIds`(見該檔案開頭「唯一的例外是 categoryId」段落),這裡直接
// 沿用、不重新定義 id 常數。
//
// 專案目前沒有 Drift `Categories` 表或對應的 `ExerciseCategory` domain
// model/repository——`seed_data.dart` 只把 categoryId 當字串常數用。選動作器
// 是唯一需要「分類清單 + 顯示名稱」的地方,所以在 feature 內部自己定義一份
// 極簡的展示用清單,不新增 data 層檔案(brief 範圍禁止動 data/)。
import '../../../data/db/seed_data.dart';

/// 單一分類的展示用資料:固定 id + 中文顯示名稱。
class ExercisePickerCategory {
  const ExercisePickerCategory({required this.id, required this.name});

  final String id;
  final String name;
}

/// 六個分類,順序對照 iOS/brief:胸/背/腿/肩/手臂/核心。
const List<ExercisePickerCategory> kExercisePickerCategories = [
  ExercisePickerCategory(id: SeedCategoryIds.chest, name: '胸'),
  ExercisePickerCategory(id: SeedCategoryIds.back, name: '背'),
  ExercisePickerCategory(id: SeedCategoryIds.legs, name: '腿'),
  ExercisePickerCategory(id: SeedCategoryIds.shoulders, name: '肩'),
  ExercisePickerCategory(id: SeedCategoryIds.arms, name: '手臂'),
  ExercisePickerCategory(id: SeedCategoryIds.core, name: '核心'),
];
