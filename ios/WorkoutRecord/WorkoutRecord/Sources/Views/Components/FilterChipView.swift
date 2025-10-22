import SwiftUI

/// 通用篩選晶片元件
/// 用於篩選選項的顯示與選擇
struct FilterChipView: View {
    let title: String
    let isSelected: Bool
    var color: Color = .blue
    var showIndicator: Bool = true
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if showIndicator {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? color.opacity(0.2) : Color(.secondarySystemBackground))
            .foregroundColor(isSelected ? color : .primary)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ScrollView(.horizontal) {
        HStack(spacing: 8) {
            FilterChipView(
                title: "全部",
                isSelected: true,
                color: .blue,
                showIndicator: false
            ) {
                print("全部")
            }
            
            FilterChipView(
                title: "胸部",
                isSelected: false,
                color: .red
            ) {
                print("胸部")
            }
            
            FilterChipView(
                title: "背部",
                isSelected: true,
                color: .green
            ) {
                print("背部")
            }
            
            FilterChipView(
                title: "腿部",
                isSelected: false,
                color: .orange
            ) {
                print("腿部")
            }
        }
    }
    .padding()
}

