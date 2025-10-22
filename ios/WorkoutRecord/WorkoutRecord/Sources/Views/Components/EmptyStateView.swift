import SwiftUI

/// 通用空狀態視圖元件
/// 用於顯示無數據時的提示訊息
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionButton: ActionButton? = nil
    
    struct ActionButton {
        let title: String
        let icon: String?
        let action: () -> Void
        
        init(title: String, icon: String? = nil, action: @escaping () -> Void) {
            self.title = title
            self.icon = icon
            self.action = action
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            if let button = actionButton {
                Button {
                    button.action()
                } label: {
                    HStack {
                        if let icon = button.icon {
                            Image(systemName: icon)
                        }
                        Text(button.title)
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    EmptyStateView(
        icon: "figure.strengthtraining.traditional",
        title: "尚無訓練記錄",
        message: "完成你的第一次訓練吧！",
        actionButton: .init(
            title: "開始訓練",
            icon: "plus.circle.fill",
            action: { print("開始訓練") }
        )
    )
}

