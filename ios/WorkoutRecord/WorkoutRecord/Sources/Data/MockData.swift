import Foundation

/// Mock data for development and testing
struct MockData {
    
    // MARK: - Exercise Categories
    static let categories: [ExerciseCategory] = [
        ExerciseCategory(id: UUID(), name: "胸部", nameEn: "Chest", displayOrder: 1),
        ExerciseCategory(id: UUID(), name: "背部", nameEn: "Back", displayOrder: 2),
        ExerciseCategory(id: UUID(), name: "腿部", nameEn: "Legs", displayOrder: 3),
        ExerciseCategory(id: UUID(), name: "肩部", nameEn: "Shoulders", displayOrder: 4),
        ExerciseCategory(id: UUID(), name: "手臂", nameEn: "Arms", displayOrder: 5),
        ExerciseCategory(id: UUID(), name: "核心", nameEn: "Core", displayOrder: 6)
    ]
    
    // MARK: - Exercises by Category
    
    /// Chest exercises (胸部)
    static let chestExercises: [Exercise] = {
        let categoryId = categories[0].id
        return [
            Exercise(name: "槓鈴臥推", nameEn: "Barbell Bench Press", categoryId: categoryId, type: .freeWeight, muscleGroups: ["胸大肌", "三角肌前束", "肱三頭肌"], isSystem: true),
            Exercise(name: "啞鈴臥推", nameEn: "Dumbbell Bench Press", categoryId: categoryId, type: .freeWeight, muscleGroups: ["胸大肌", "三角肌前束"], isSystem: true),
            Exercise(name: "上斜槓鈴臥推", nameEn: "Incline Barbell Press", categoryId: categoryId, type: .freeWeight, muscleGroups: ["胸大肌上側"], isSystem: true),
            Exercise(name: "上斜啞鈴臥推", nameEn: "Incline Dumbbell Press", categoryId: categoryId, type: .freeWeight, muscleGroups: ["胸大肌上側"], isSystem: true),
            Exercise(name: "下斜槓鈴臥推", nameEn: "Decline Barbell Press", categoryId: categoryId, type: .freeWeight, muscleGroups: ["胸大肌下側"], isSystem: true),
            Exercise(name: "啞鈴飛鳥", nameEn: "Dumbbell Fly", categoryId: categoryId, type: .freeWeight, muscleGroups: ["胸大肌"], isSystem: true),
            Exercise(name: "上斜啞鈴飛鳥", nameEn: "Incline Dumbbell Fly", categoryId: categoryId, type: .freeWeight, muscleGroups: ["胸大肌上側"], isSystem: true),
            Exercise(name: "胸推機", nameEn: "Chest Press Machine", categoryId: categoryId, type: .machine, muscleGroups: ["胸大肌"], isSystem: true),
            Exercise(name: "蝴蝶機", nameEn: "Pec Deck Fly", categoryId: categoryId, type: .machine, muscleGroups: ["胸大肌"], isSystem: true),
            Exercise(name: "Cable 飛鳥", nameEn: "Cable Crossover", categoryId: categoryId, type: .machine, muscleGroups: ["胸大肌"], isSystem: true),
            Exercise(name: "伏地挺身", nameEn: "Push-up", categoryId: categoryId, type: .bodyweight, muscleGroups: ["胸大肌", "三角肌", "肱三頭肌"], isSystem: true),
            Exercise(name: "雙槓撐體", nameEn: "Dips", categoryId: categoryId, type: .bodyweight, muscleGroups: ["胸大肌下側", "肱三頭肌"], isSystem: true)
        ]
    }()
    
    /// Back exercises (背部)
    static let backExercises: [Exercise] = {
        let categoryId = categories[1].id
        return [
            Exercise(name: "硬舉", nameEn: "Deadlift", categoryId: categoryId, type: .freeWeight, muscleGroups: ["下背", "臀部", "腿後肌"], isSystem: true),
            Exercise(name: "槓鈴划船", nameEn: "Barbell Row", categoryId: categoryId, type: .freeWeight, muscleGroups: ["背闊肌", "斜方肌"], isSystem: true),
            Exercise(name: "啞鈴划船", nameEn: "Dumbbell Row", categoryId: categoryId, type: .freeWeight, muscleGroups: ["背闊肌"], isSystem: true),
            Exercise(name: "T 槓划船", nameEn: "T-Bar Row", categoryId: categoryId, type: .freeWeight, muscleGroups: ["背闊肌", "斜方肌"], isSystem: true),
            Exercise(name: "引體向上", nameEn: "Pull-up", categoryId: categoryId, type: .bodyweight, muscleGroups: ["背闊肌", "二頭肌"], isSystem: true),
            Exercise(name: "滑輪下拉", nameEn: "Lat Pulldown", categoryId: categoryId, type: .machine, muscleGroups: ["背闊肌"], isSystem: true),
            Exercise(name: "坐姿划船", nameEn: "Seated Cable Row", categoryId: categoryId, type: .machine, muscleGroups: ["背闊肌", "斜方肌"], isSystem: true),
            Exercise(name: "單臂啞鈴划船", nameEn: "One-Arm Dumbbell Row", categoryId: categoryId, type: .freeWeight, muscleGroups: ["背闊肌"], isSystem: true),
            Exercise(name: "直臂下壓", nameEn: "Straight Arm Pulldown", categoryId: categoryId, type: .machine, muscleGroups: ["背闊肌"], isSystem: true),
            Exercise(name: "臉拉", nameEn: "Face Pull", categoryId: categoryId, type: .machine, muscleGroups: ["後三角肌", "上背"], isSystem: true),
            Exercise(name: "反向飛鳥", nameEn: "Reverse Fly", categoryId: categoryId, type: .freeWeight, muscleGroups: ["後三角肌", "上背"], isSystem: true)
        ]
    }()
    
    /// Leg exercises (腿部)
    static let legExercises: [Exercise] = {
        let categoryId = categories[2].id
        return [
            Exercise(name: "深蹲", nameEn: "Squat", categoryId: categoryId, type: .freeWeight, muscleGroups: ["股四頭肌", "臀大肌"], isSystem: true),
            Exercise(name: "前蹲", nameEn: "Front Squat", categoryId: categoryId, type: .freeWeight, muscleGroups: ["股四頭肌"], isSystem: true),
            Exercise(name: "硬舉", nameEn: "Deadlift", categoryId: categoryId, type: .freeWeight, muscleGroups: ["腿後肌", "臀部", "下背"], isSystem: true),
            Exercise(name: "羅馬尼亞硬舉", nameEn: "Romanian Deadlift", categoryId: categoryId, type: .freeWeight, muscleGroups: ["腿後肌", "臀部"], isSystem: true),
            Exercise(name: "腿推機", nameEn: "Leg Press", categoryId: categoryId, type: .machine, muscleGroups: ["股四頭肌", "臀大肌"], isSystem: true),
            Exercise(name: "腿伸屈", nameEn: "Leg Extension", categoryId: categoryId, type: .machine, muscleGroups: ["股四頭肌"], isSystem: true),
            Exercise(name: "腿彎舉", nameEn: "Leg Curl", categoryId: categoryId, type: .machine, muscleGroups: ["腿後肌"], isSystem: true),
            Exercise(name: "保加利亞分腿蹲", nameEn: "Bulgarian Split Squat", categoryId: categoryId, type: .freeWeight, muscleGroups: ["股四頭肌", "臀大肌"], isSystem: true),
            Exercise(name: "箭步蹲", nameEn: "Lunge", categoryId: categoryId, type: .freeWeight, muscleGroups: ["股四頭肌", "臀大肌"], isSystem: true),
            Exercise(name: "臀推", nameEn: "Hip Thrust", categoryId: categoryId, type: .freeWeight, muscleGroups: ["臀大肌"], isSystem: true),
            Exercise(name: "提踵", nameEn: "Calf Raise", categoryId: categoryId, type: .freeWeight, muscleGroups: ["小腿"], isSystem: true),
            Exercise(name: "坐姿提踵", nameEn: "Seated Calf Raise", categoryId: categoryId, type: .machine, muscleGroups: ["小腿"], isSystem: true)
        ]
    }()
    
    /// Shoulder exercises (肩部)
    static let shoulderExercises: [Exercise] = {
        let categoryId = categories[3].id
        return [
            Exercise(name: "肩推", nameEn: "Overhead Press", categoryId: categoryId, type: .freeWeight, muscleGroups: ["三角肌", "肱三頭肌"], isSystem: true),
            Exercise(name: "啞鈴肩推", nameEn: "Dumbbell Shoulder Press", categoryId: categoryId, type: .freeWeight, muscleGroups: ["三角肌"], isSystem: true),
            Exercise(name: "阿諾推舉", nameEn: "Arnold Press", categoryId: categoryId, type: .freeWeight, muscleGroups: ["三角肌"], isSystem: true),
            Exercise(name: "側平舉", nameEn: "Lateral Raise", categoryId: categoryId, type: .freeWeight, muscleGroups: ["三角肌中束"], isSystem: true),
            Exercise(name: "前平舉", nameEn: "Front Raise", categoryId: categoryId, type: .freeWeight, muscleGroups: ["三角肌前束"], isSystem: true),
            Exercise(name: "俯身側平舉", nameEn: "Bent-Over Lateral Raise", categoryId: categoryId, type: .freeWeight, muscleGroups: ["三角肌後束"], isSystem: true),
            Exercise(name: "直立划船", nameEn: "Upright Row", categoryId: categoryId, type: .freeWeight, muscleGroups: ["三角肌", "斜方肌"], isSystem: true),
            Exercise(name: "肩推機", nameEn: "Shoulder Press Machine", categoryId: categoryId, type: .machine, muscleGroups: ["三角肌"], isSystem: true),
            Exercise(name: "Cable 側平舉", nameEn: "Cable Lateral Raise", categoryId: categoryId, type: .machine, muscleGroups: ["三角肌中束"], isSystem: true),
            Exercise(name: "臉拉", nameEn: "Face Pull", categoryId: categoryId, type: .machine, muscleGroups: ["三角肌後束"], isSystem: true)
        ]
    }()
    
    /// Arm exercises (手臂)
    static let armExercises: [Exercise] = {
        let categoryId = categories[4].id
        return [
            Exercise(name: "槓鈴彎舉", nameEn: "Barbell Curl", categoryId: categoryId, type: .freeWeight, muscleGroups: ["二頭肌"], isSystem: true),
            Exercise(name: "啞鈴彎舉", nameEn: "Dumbbell Curl", categoryId: categoryId, type: .freeWeight, muscleGroups: ["二頭肌"], isSystem: true),
            Exercise(name: "錘式彎舉", nameEn: "Hammer Curl", categoryId: categoryId, type: .freeWeight, muscleGroups: ["二頭肌", "前臂"], isSystem: true),
            Exercise(name: "集中彎舉", nameEn: "Concentration Curl", categoryId: categoryId, type: .freeWeight, muscleGroups: ["二頭肌"], isSystem: true),
            Exercise(name: "三頭下壓", nameEn: "Tricep Pushdown", categoryId: categoryId, type: .machine, muscleGroups: ["肱三頭肌"], isSystem: true),
            Exercise(name: "過頭三頭伸展", nameEn: "Overhead Tricep Extension", categoryId: categoryId, type: .freeWeight, muscleGroups: ["肱三頭肌"], isSystem: true),
            Exercise(name: "窄握臥推", nameEn: "Close-Grip Bench Press", categoryId: categoryId, type: .freeWeight, muscleGroups: ["肱三頭肌", "胸部"], isSystem: true),
            Exercise(name: "啞鈴三頭後踢", nameEn: "Tricep Kickback", categoryId: categoryId, type: .freeWeight, muscleGroups: ["肱三頭肌"], isSystem: true),
            Exercise(name: "Cable 彎舉", nameEn: "Cable Curl", categoryId: categoryId, type: .machine, muscleGroups: ["二頭肌"], isSystem: true),
            Exercise(name: "EZ Bar 彎舉", nameEn: "EZ Bar Curl", categoryId: categoryId, type: .freeWeight, muscleGroups: ["二頭肌"], isSystem: true),
            Exercise(name: "反握彎舉", nameEn: "Reverse Curl", categoryId: categoryId, type: .freeWeight, muscleGroups: ["前臂", "二頭肌"], isSystem: true)
        ]
    }()
    
    /// Core exercises (核心)
    static let coreExercises: [Exercise] = {
        let categoryId = categories[5].id
        return [
            Exercise(name: "捲腹", nameEn: "Crunch", categoryId: categoryId, type: .bodyweight, muscleGroups: ["腹直肌"], isSystem: true),
            Exercise(name: "仰臥起坐", nameEn: "Sit-up", categoryId: categoryId, type: .bodyweight, muscleGroups: ["腹直肌"], isSystem: true),
            Exercise(name: "棒式", nameEn: "Plank", categoryId: categoryId, type: .bodyweight, muscleGroups: ["核心"], isSystem: true),
            Exercise(name: "側棒式", nameEn: "Side Plank", categoryId: categoryId, type: .bodyweight, muscleGroups: ["腹斜肌"], isSystem: true),
            Exercise(name: "懸吊舉腿", nameEn: "Hanging Leg Raise", categoryId: categoryId, type: .bodyweight, muscleGroups: ["下腹"], isSystem: true),
            Exercise(name: "捲腹機", nameEn: "Ab Crunch Machine", categoryId: categoryId, type: .machine, muscleGroups: ["腹直肌"], isSystem: true),
            Exercise(name: "Cable 捲腹", nameEn: "Cable Crunch", categoryId: categoryId, type: .machine, muscleGroups: ["腹直肌"], isSystem: true),
            Exercise(name: "Russian Twist", nameEn: "Russian Twist", categoryId: categoryId, type: .bodyweight, muscleGroups: ["腹斜肌"], isSystem: true),
            Exercise(name: "登山者式", nameEn: "Mountain Climber", categoryId: categoryId, type: .bodyweight, muscleGroups: ["核心"], isSystem: true),
            Exercise(name: "腹輪", nameEn: "Ab Wheel", categoryId: categoryId, type: .bodyweight, muscleGroups: ["核心"], isSystem: true)
        ]
    }()
    
    // MARK: - All Exercises
    static var allExercises: [Exercise] {
        return chestExercises + backExercises + legExercises + shoulderExercises + armExercises + coreExercises
    }
    
    // MARK: - Get exercises by category
    static func exercises(for category: ExerciseCategory) -> [Exercise] {
        switch category.name {
        case "胸部": return chestExercises
        case "背部": return backExercises
        case "腿部": return legExercises
        case "肩部": return shoulderExercises
        case "手臂": return armExercises
        case "核心": return coreExercises
        default: return []
        }
    }
}

