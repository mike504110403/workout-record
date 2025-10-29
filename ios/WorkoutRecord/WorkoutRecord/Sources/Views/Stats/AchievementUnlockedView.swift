import SwiftUI

/// 成就解鎖彈窗
struct AchievementUnlockedView: View {
    let achievement: Achievement
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            // 成就卡片
            VStack(spacing: 24) {
                // 頂部裝飾
                Image(systemName: "star.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.yellow)
                    .shadow(color: .yellow.opacity(0.3), radius: 20)
                
                VStack(spacing: 12) {
                    Text("🎉 成就解鎖！")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    // 成就圖標
                    ZStack {
                        Circle()
                            .fill(achievement.color.opacity(0.2))
                            .frame(width: 100, height: 100)
                        
                        Text(achievement.icon)
                            .font(.system(size: 50))
                    }
                    
                    // 成就標題
                    Text(achievement.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    // 成就描述
                    Text(achievement.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // 關閉按鈕
                Button {
                    isPresented = false
                } label: {
                    Text("太棒了！")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(achievement.color)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.2), radius: 20)
            )
            .padding(.horizontal, 40)
        }
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isPresented)
    }
}

// MARK: - Achievement Extension for Color

extension Achievement {
    var color: Color {
        switch category {
        case .powerlifting:
            return .orange
        case .volume:
            return .blue
        case .consistency:
            return .red
        case .special:
            return .purple
        }
    }
}

#Preview {
    AchievementUnlockedView(
        achievement: Achievement(
            id: "bench_100kg",
            title: "臥推破百",
            description: "臥推 1RM 達到 100kg",
            icon: "💪",
            category: .powerlifting,
            requirement: .oneRM(.benchPress, 100),
            isUnlocked: true,
            unlockedAt: Date(),
            progress: 1.0
        ),
        isPresented: .constant(true)
    )
}

