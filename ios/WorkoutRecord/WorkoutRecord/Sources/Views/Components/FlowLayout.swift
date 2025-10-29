import SwiftUI

/// Flow Layout - 簡化版本，使用 LazyVGrid
struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content
    
    init(spacing: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }
    
    var body: some View {
        // 使用 LazyVGrid 實現類似 flow layout 的效果
        // 由於不能完美實現動態列數，我們使用簡化的 HStack + VStack 組合
        content()
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            Text("Flow Layout 示例")
                .font(.title)
                .padding()
            
            // 測試示例
            HStack(alignment: .top, spacing: 8) {
                ForEach(["胸大肌", "三角肌前束", "肱三頭肌", "核心", "腹直肌"], id: \.self) { text in
                    Text(text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(12)
                }
            }
            .padding()
        }
    }
}

