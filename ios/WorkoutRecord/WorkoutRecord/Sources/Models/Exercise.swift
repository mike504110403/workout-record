import Foundation

// MARK: - Muscle Group (別名)
typealias MuscleGroup = Exercise.PrimaryMuscleGroup

struct Exercise: Identifiable, Codable {
    let id: UUID
    var name: String
    var nameEn: String?
    let categoryId: UUID
    var category: ExerciseCategory?
    var type: ExerciseType
    var muscleGroups: [String]  // 舊的肌群欄位（向後兼容）
    var targetMuscles: [DetailedMuscleGroup]  // 新的詳細肌群（支持多選）
    var primaryMuscleGroup: PrimaryMuscleGroup?  // 主要肌群分類
    var movementPattern: MovementPattern?  // 動作模式
    var description: String?
    var videoURL: String?
    var imageURL: String?
    let isSystem: Bool  // Whether it's a system default exercise
    let userId: UUID?  // Creator ID for custom exercises
    var isActive: Bool
    var displayOrder: Int?
    let createdAt: Date
    var updatedAt: Date
    
    // User-specific settings (not from API)
    var isFavorite: Bool = false
    var isHidden: Bool = false
    
    enum ExerciseType: String, Codable, CaseIterable {
        case machine = "machine"
        case freeWeight = "free_weight"
        case bodyweight = "bodyweight"
        
        var displayName: String {
            switch self {
            case .machine: return "器材"
            case .freeWeight: return "自由重量"
            case .bodyweight: return "徒手"
            }
        }
    }
    
    // 動作模式
    enum MovementPattern: String, Codable, CaseIterable {
        case push = "push"              // 推
        case pull = "pull"              // 拉
        case squat = "squat"            // 蹲
        case hinge = "hinge"            // 髖鉸鏈
        case carry = "carry"            // 負重行走
        case rotation = "rotation"      // 旋轉
        case isolation = "isolation"    // 孤立
        
        var displayName: String {
            switch self {
            case .push: return "推"
            case .pull: return "拉"
            case .squat: return "蹲"
            case .hinge: return "髖鉸鏈"
            case .carry: return "負重行走"
            case .rotation: return "旋轉"
            case .isolation: return "孤立"
            }
        }
        
        var icon: String {
            switch self {
            case .push: return "arrow.forward.circle"
            case .pull: return "arrow.backward.circle"
            case .squat: return "arrow.down.circle"
            case .hinge: return "arrow.down.right.circle"
            case .carry: return "figure.walk"
            case .rotation: return "arrow.triangle.2.circlepath"
            case .isolation: return "scope"
            }
        }
    }
    
    // 主要肌群
    enum PrimaryMuscleGroup: String, Codable, CaseIterable {
        case chest = "chest"          // 胸
        case back = "back"            // 背
        case legs = "legs"            // 腿
        case shoulders = "shoulders"  // 肩
        case arms = "arms"            // 手臂
        case core = "core"            // 核心
        case glutes = "glutes"        // 臀部
        case fullBody = "full_body"   // 全身
        
        var displayName: String {
            switch self {
            case .chest: return "胸"
            case .back: return "背"
            case .legs: return "腿"
            case .shoulders: return "肩"
            case .arms: return "手臂"
            case .core: return "核心"
            case .glutes: return "臀部"
            case .fullBody: return "全身"
            }
        }
        
        var color: String {
            switch self {
            case .chest: return "red"
            case .back: return "blue"
            case .legs: return "green"
            case .shoulders: return "orange"
            case .arms: return "purple"
            case .core: return "yellow"
            case .glutes: return "pink"
            case .fullBody: return "gray"
            }
        }
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        nameEn: String? = nil,
        categoryId: UUID,
        category: ExerciseCategory? = nil,
        type: ExerciseType,
        muscleGroups: [String] = [],
        targetMuscles: [DetailedMuscleGroup] = [],
        primaryMuscleGroup: PrimaryMuscleGroup? = nil,
        movementPattern: MovementPattern? = nil,
        description: String? = nil,
        videoURL: String? = nil,
        imageURL: String? = nil,
        isSystem: Bool = false,
        userId: UUID? = nil,
        isActive: Bool = true,
        displayOrder: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.nameEn = nameEn
        self.categoryId = categoryId
        self.category = category
        self.type = type
        self.muscleGroups = muscleGroups
        self.targetMuscles = targetMuscles
        self.primaryMuscleGroup = primaryMuscleGroup
        self.movementPattern = movementPattern
        self.description = description
        self.videoURL = videoURL
        self.imageURL = imageURL
        self.isSystem = isSystem
        self.userId = userId
        self.isActive = isActive
        self.displayOrder = displayOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ExerciseCategory: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let nameEn: String?
    var displayOrder: Int
    let isSystem: Bool
    let createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        nameEn: String? = nil,
        displayOrder: Int = 0,
        isSystem: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.nameEn = nameEn
        self.displayOrder = displayOrder
        self.isSystem = isSystem
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Mock Data
extension Exercise {
    static let mockExercises: [Exercise] = [
        Exercise(
            name: "槓鈴臥推",
            nameEn: "Barbell Bench Press",
            categoryId: UUID(),
            type: .freeWeight,
            muscleGroups: ["胸大肌", "三角肌前束", "肱三頭肌"],
            description: "經典的胸部訓練動作",
            isSystem: true
        ),
        Exercise(
            name: "深蹲",
            nameEn: "Squat",
            categoryId: UUID(),
            type: .freeWeight,
            muscleGroups: ["股四頭肌", "臀大肌", "腿後肌"],
            description: "腿部訓練之王",
            isSystem: true
        ),
        Exercise(
            name: "硬舉",
            nameEn: "Deadlift",
            categoryId: UUID(),
            type: .freeWeight,
            muscleGroups: ["背部", "臀部", "腿後肌"],
            description: "全身性的複合動作",
            isSystem: true
        )
    ]
}

extension ExerciseCategory {
    static let mockCategories: [ExerciseCategory] = [
        ExerciseCategory(name: "胸部", nameEn: "Chest", displayOrder: 1),
        ExerciseCategory(name: "背部", nameEn: "Back", displayOrder: 2),
        ExerciseCategory(name: "腿部", nameEn: "Legs", displayOrder: 3),
        ExerciseCategory(name: "肩部", nameEn: "Shoulders", displayOrder: 4),
        ExerciseCategory(name: "手臂", nameEn: "Arms", displayOrder: 5),
        ExerciseCategory(name: "核心", nameEn: "Core", displayOrder: 6)
    ]
}

