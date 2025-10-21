import Foundation
import SwiftUI

/// 詳細肌群枚舉（基於解剖學和健身常用分類）
enum DetailedMuscleGroup: String, Codable, CaseIterable, Identifiable {
    var id: String { rawValue }
    
    // MARK: - 胸部肌群
    case upperChest = "upper_chest"           // 上胸
    case midChest = "mid_chest"               // 中胸
    case lowerChest = "lower_chest"           // 下胸
    case innerChest = "inner_chest"           // 內胸
    case outerChest = "outer_chest"           // 外胸
    
    // MARK: - 背部肌群
    case lats = "lats"                        // 背闊肌
    case traps = "traps"                      // 斜方肌
    case rhomboids = "rhomboids"              // 菱形肌
    case erecterSpinae = "erecter_spinae"     // 豎脊肌
    case teresMajor = "teres_major"           // 大圓肌
    case infraspinatus = "infraspinatus"      // 棘下肌
    
    // MARK: - 腿部肌群
    case quads = "quads"                      // 股四頭肌
    case hamstrings = "hamstrings"            // 腿後肌群
    case glutes = "glutes"                    // 臀大肌
    case calves = "calves"                    // 小腿肌
    case adductors = "adductors"              // 內收肌
    case abductors = "abductors"              // 外展肌
    
    // MARK: - 肩部肌群
    case anteriorDelt = "anterior_delt"       // 前三角肌
    case lateralDelt = "lateral_delt"         // 中三角肌
    case posteriorDelt = "posterior_delt"     // 後三角肌
    case rotatorCuff = "rotator_cuff"         // 旋轉肌袖
    
    // MARK: - 手臂肌群
    case biceps = "biceps"                    // 肱二頭肌
    case triceps = "triceps"                  // 肱三頭肌
    case forearms = "forearms"                // 前臂肌群
    case brachialis = "brachialis"            // 肱肌
    
    // MARK: - 核心肌群
    case rectusAbdominis = "rectus_abdominis" // 腹直肌
    case obliques = "obliques"                // 腹斜肌
    case transverseAbdominis = "transverse"   // 腹橫肌
    case lowerBack = "lower_back"             // 下背
    case hipFlexors = "hip_flexors"           // 髖屈肌
    
    // MARK: - 全身
    case fullBody = "full_body"               // 全身
    
    var displayName: String {
        switch self {
        // 胸部
        case .upperChest: return "上胸"
        case .midChest: return "中胸"
        case .lowerChest: return "下胸"
        case .innerChest: return "內胸"
        case .outerChest: return "外胸"
        
        // 背部
        case .lats: return "背闊肌"
        case .traps: return "斜方肌"
        case .rhomboids: return "菱形肌"
        case .erecterSpinae: return "豎脊肌"
        case .teresMajor: return "大圓肌"
        case .infraspinatus: return "棘下肌"
        
        // 腿部
        case .quads: return "股四頭肌"
        case .hamstrings: return "腿後肌"
        case .glutes: return "臀大肌"
        case .calves: return "小腿"
        case .adductors: return "內收肌"
        case .abductors: return "外展肌"
        
        // 肩部
        case .anteriorDelt: return "前三角"
        case .lateralDelt: return "中三角"
        case .posteriorDelt: return "後三角"
        case .rotatorCuff: return "旋轉肌"
        
        // 手臂
        case .biceps: return "肱二頭"
        case .triceps: return "肱三頭"
        case .forearms: return "前臂"
        case .brachialis: return "肱肌"
        
        // 核心
        case .rectusAbdominis: return "腹直肌"
        case .obliques: return "腹斜肌"
        case .transverseAbdominis: return "腹橫肌"
        case .lowerBack: return "下背"
        case .hipFlexors: return "髖屈肌"
        
        // 全身
        case .fullBody: return "全身"
        }
    }
    
    var displayNameEn: String {
        switch self {
        // 胸部
        case .upperChest: return "Upper Chest"
        case .midChest: return "Mid Chest"
        case .lowerChest: return "Lower Chest"
        case .innerChest: return "Inner Chest"
        case .outerChest: return "Outer Chest"
        
        // 背部
        case .lats: return "Latissimus Dorsi"
        case .traps: return "Trapezius"
        case .rhomboids: return "Rhomboids"
        case .erecterSpinae: return "Erector Spinae"
        case .teresMajor: return "Teres Major"
        case .infraspinatus: return "Infraspinatus"
        
        // 腿部
        case .quads: return "Quadriceps"
        case .hamstrings: return "Hamstrings"
        case .glutes: return "Glutes"
        case .calves: return "Calves"
        case .adductors: return "Adductors"
        case .abductors: return "Abductors"
        
        // 肩部
        case .anteriorDelt: return "Anterior Deltoid"
        case .lateralDelt: return "Lateral Deltoid"
        case .posteriorDelt: return "Posterior Deltoid"
        case .rotatorCuff: return "Rotator Cuff"
        
        // 手臂
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .brachialis: return "Brachialis"
        
        // 核心
        case .rectusAbdominis: return "Rectus Abdominis"
        case .obliques: return "Obliques"
        case .transverseAbdominis: return "Transverse Abdominis"
        case .lowerBack: return "Lower Back"
        case .hipFlexors: return "Hip Flexors"
        
        // 全身
        case .fullBody: return "Full Body"
        }
    }
    
    /// 所屬的主要肌群分類
    var category: Exercise.PrimaryMuscleGroup {
        switch self {
        case .upperChest, .midChest, .lowerChest, .innerChest, .outerChest:
            return .chest
        case .lats, .traps, .rhomboids, .erecterSpinae, .teresMajor, .infraspinatus:
            return .back
        case .quads, .hamstrings, .adductors, .abductors:
            return .legs
        case .glutes:
            return .glutes
        case .anteriorDelt, .lateralDelt, .posteriorDelt, .rotatorCuff:
            return .shoulders
        case .biceps, .triceps, .forearms, .brachialis:
            return .arms
        case .rectusAbdominis, .obliques, .transverseAbdominis, .lowerBack, .hipFlexors:
            return .core
        case .calves:
            return .legs
        case .fullBody:
            return .fullBody
        }
    }
    
    /// 顏色（根據所屬分類）
    var color: Color {
        switch category {
        case .chest: return .red
        case .back: return .blue
        case .legs: return .green
        case .shoulders: return .orange
        case .arms: return .purple
        case .core: return .yellow
        case .glutes: return .pink
        case .fullBody: return .gray
        }
    }
    
    /// 根據分類獲取對應的肌群列表
    static func muscles(for category: Exercise.PrimaryMuscleGroup) -> [DetailedMuscleGroup] {
        switch category {
        case .chest:
            return [.upperChest, .midChest, .lowerChest, .innerChest, .outerChest]
        case .back:
            return [.lats, .traps, .rhomboids, .erecterSpinae, .teresMajor, .infraspinatus]
        case .legs:
            return [.quads, .hamstrings, .calves, .adductors, .abductors]
        case .glutes:
            return [.glutes]
        case .shoulders:
            return [.anteriorDelt, .lateralDelt, .posteriorDelt, .rotatorCuff]
        case .arms:
            return [.biceps, .triceps, .forearms, .brachialis]
        case .core:
            return [.rectusAbdominis, .obliques, .transverseAbdominis, .lowerBack, .hipFlexors]
        case .fullBody:
            return [.fullBody]
        }
    }
    
    /// 根據分類名稱獲取對應的肌群列表
    static func muscles(forCategoryName name: String) -> [DetailedMuscleGroup] {
        let category: Exercise.PrimaryMuscleGroup
        switch name {
        case "胸部", "Chest":
            category = .chest
        case "背部", "Back":
            category = .back
        case "腿部", "Legs":
            category = .legs
        case "臀部", "Glutes":
            category = .glutes
        case "肩部", "Shoulders":
            category = .shoulders
        case "手臂", "Arms":
            category = .arms
        case "核心", "Core":
            category = .core
        default:
            return DetailedMuscleGroup.allCases
        }
        return muscles(for: category)
    }
}

