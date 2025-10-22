import SwiftUI

/// 通用載入狀態視圖
struct LoadingView: View {
    var message: String = "載入中..."
    var showBackground: Bool = false
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(showBackground ? Color(.systemBackground) : Color.clear)
    }
}

#Preview {
    LoadingView(message: "正在載入訓練記錄...")
}

