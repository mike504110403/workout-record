import SwiftUI

/// 成就系統視圖
struct AchievementsView: View {
    @StateObject private var viewModel = AchievementsViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 成就進度總覽
                progressCard
                
                // 各分類成就
                ForEach(AchievementCategory.allCases) { category in
                    AchievementCategorySection(
                        category: category,
                        achievements: viewModel.achievements(for: category)
                    )
                }
            }
            .padding()
        }
        .navigationTitle("成就")
        .onAppear {
            viewModel.refresh()
        }
        .overlay {
            if viewModel.isLoading {
                LoadingView(message: "檢查成就中...")
            }
        }
    }
    
    // MARK: - Progress Card
    
    private var progressCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("成就進度")
                        .font(.headline)
                    
                    Text("\(viewModel.unlockedCount) / \(viewModel.totalAchievements)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(String(format: "%.0f%%", viewModel.completionPercentage))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            ProgressView(value: viewModel.completionPercentage, total: 100)
                .tint(.blue)
                .scaleEffect(y: 2)
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
    }
}

// MARK: - Category Section

struct AchievementCategorySection: View {
    let category: AchievementCategory
    let achievements: [Achievement]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 分類標題
            HStack {
                Image(systemName: category.icon)
                    .foregroundColor(category.color)
                
                Text(category.rawValue)
                    .font(.title3)
                    .fontWeight(.bold)
                
                Spacer()
                
                Text("\(unlockedCount) / \(achievements.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // 成就列表
            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: 12
            ) {
                ForEach(achievements) { achievement in
                    AchievementCard(achievement: achievement)
                }
            }
        }
    }
    
    private var unlockedCount: Int {
        achievements.filter { $0.isUnlocked }.count
    }
}

// MARK: - Achievement Card

struct AchievementCard: View {
    let achievement: Achievement
    
    var body: some View {
        VStack(spacing: 12) {
            // 圖示
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 60, height: 60)
                
                Text(achievement.icon)
                    .font(.system(size: 30))
                    .grayscale(achievement.isUnlocked ? 0 : 1)
                    .opacity(achievement.isUnlocked ? 1.0 : 0.3)
            }
            
            // 標題
            Text(achievement.title)
                .font(.caption)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .foregroundColor(achievement.isUnlocked ? .primary : .secondary)
            
            // 描述
            Text(achievement.description)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            // 進度條（未解鎖時顯示）
            if !achievement.isUnlocked && achievement.progress > 0 {
                VStack(spacing: 4) {
                    ProgressView(value: achievement.progress)
                        .tint(achievement.category.color)
                    
                    Text(String(format: "%.0f%%", achievement.progress * 100))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // 解鎖日期
            if let unlockedDate = achievement.unlockedAt {
                Text(unlockedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    achievement.isUnlocked ? achievement.category.color : Color.clear,
                    lineWidth: 2
                )
        )
        .shadow(
            color: achievement.isUnlocked ? achievement.category.color.opacity(0.2) : .black.opacity(0.05),
            radius: achievement.isUnlocked ? 8 : 5,
            x: 0,
            y: 2
        )
    }
    
    private var backgroundColor: Color {
        if achievement.isUnlocked {
            return achievement.category.color.opacity(0.2)
        } else {
            return Color(.secondarySystemBackground)
        }
    }
}

// MARK: - Achievement Share Card

struct AchievementShareCard: View {
    let achievement: Achievement
    
    var body: some View {
        VStack(spacing: 20) {
            // App Logo/Icon
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 60))
                .foregroundColor(.white)
            
            // 成就圖示
            Text(achievement.icon)
                .font(.system(size: 80))
            
            // 成就資訊
            VStack(spacing: 8) {
                Text("成就解鎖")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.8))
                
                Text(achievement.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(achievement.description)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
            }
            
            // 日期
            if let date = achievement.unlockedAt {
                Text(date.formatted(date: .long, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Text("WorkoutRecord")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(40)
        .frame(width: 400, height: 500)
        .background(
            LinearGradient(
                colors: [achievement.category.color, achievement.category.color.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

#Preview {
    NavigationStack {
        AchievementsView()
    }
}

