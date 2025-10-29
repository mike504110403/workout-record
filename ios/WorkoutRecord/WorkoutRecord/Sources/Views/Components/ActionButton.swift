import SwiftUI

/// 通用操作按鈕元件
/// 支持不同樣式和尺寸
struct ActionButton: View {
    let icon: String
    let title: String
    let color: Color
    var style: ButtonStyle = .filled
    var size: ButtonSize = .medium
    let action: () -> Void
    
    enum ButtonStyle {
        case filled    // 填滿
        case outlined  // 外框
        case plain     // 純文字
    }
    
    enum ButtonSize {
        case small, medium, large
        
        var iconSize: CGFloat {
            switch self {
            case .small: return 20
            case .medium: return 24
            case .large: return 28
            }
        }
        
        var padding: CGFloat {
            switch self {
            case .small: return 8
            case .medium: return 12
            case .large: return 16
            }
        }
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: size.iconSize))
                    .foregroundColor(foregroundColor)
                    .frame(width: 50, height: 50)
                    .background(iconBackground)
                    .cornerRadius(12)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(textColor)
            }
            .frame(maxWidth: .infinity)
            .padding(size.padding)
            .background(buttonBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(strokeColor, lineWidth: style == .outlined ? 1.5 : 0)
            )
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .filled:
            return .white
        case .outlined, .plain:
            return color
        }
    }
    
    private var iconBackground: Color {
        switch style {
        case .filled:
            return color
        case .outlined, .plain:
            return color.opacity(0.1)
        }
    }
    
    private var textColor: Color {
        switch style {
        case .filled, .plain:
            return .primary
        case .outlined:
            return color
        }
    }
    
    private var buttonBackground: Color {
        switch style {
        case .filled, .outlined:
            return Color(.systemBackground)
        case .plain:
            return Color.clear
        }
    }
    
    private var strokeColor: Color {
        style == .outlined ? color : .clear
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 12) {
            ActionButton(
                icon: "scalemass.fill",
                title: "記錄體重",
                color: .blue,
                style: .filled
            ) {
                print("記錄體重")
            }
            
            ActionButton(
                icon: "figure.strengthtraining.traditional",
                title: "開始訓練",
                color: .green,
                style: .outlined
            ) {
                print("開始訓練")
            }
            
            ActionButton(
                icon: "chart.line.uptrend.xyaxis",
                title: "查看進度",
                color: .orange,
                style: .plain
            ) {
                print("查看進度")
            }
        }
    }
    .padding()
}

