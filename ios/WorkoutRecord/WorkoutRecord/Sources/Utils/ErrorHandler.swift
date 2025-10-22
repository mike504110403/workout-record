import SwiftUI
import Foundation
import Combine

// MARK: - Error Types

enum AppError: LocalizedError, Identifiable {
    case networkError(String)
    case dataError(String)
    case validationError(String)
    case permissionError(String)
    case unknownError(String)
    
    var id: String {
        switch self {
        case .networkError(let message):
            return "network_\(message.hashValue)"
        case .dataError(let message):
            return "data_\(message.hashValue)"
        case .validationError(let message):
            return "validation_\(message.hashValue)"
        case .permissionError(let message):
            return "permission_\(message.hashValue)"
        case .unknownError(let message):
            return "unknown_\(message.hashValue)"
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "網路錯誤：\(message)"
        case .dataError(let message):
            return "數據錯誤：\(message)"
        case .validationError(let message):
            return "驗證錯誤：\(message)"
        case .permissionError(let message):
            return "權限錯誤：\(message)"
        case .unknownError(let message):
            return "未知錯誤：\(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .networkError:
            return "請檢查網路連線並重試"
        case .dataError:
            return "請重新整理數據或重新啟動應用程式"
        case .validationError:
            return "請檢查輸入的數據是否正確"
        case .permissionError:
            return "請在設定中開啟所需權限"
        case .unknownError:
            return "請重新啟動應用程式或聯絡技術支援"
        }
    }
}

// MARK: - Error Handler

class ErrorHandler: ObservableObject {
    static let shared = ErrorHandler()
    
    @Published var currentError: AppError?
    @Published var errorHistory: [AppError] = []
    
    private init() {}
    
    func handle(_ error: Error) {
        let appError = convertToAppError(error)
        currentError = appError
        errorHistory.append(appError)
        
        // 記錄錯誤
        logError(appError)
    }
    
    func handle(_ appError: AppError) {
        currentError = appError
        errorHistory.append(appError)
        
        // 記錄錯誤
        logError(appError)
    }
    
    func clearError() {
        currentError = nil
    }
    
    private func convertToAppError(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        
        // 根據錯誤類型轉換
        if error.localizedDescription.contains("network") || error.localizedDescription.contains("connection") {
            return .networkError(error.localizedDescription)
        } else if error.localizedDescription.contains("data") || error.localizedDescription.contains("core data") {
            return .dataError(error.localizedDescription)
        } else if error.localizedDescription.contains("validation") || error.localizedDescription.contains("invalid") {
            return .validationError(error.localizedDescription)
        } else if error.localizedDescription.contains("permission") || error.localizedDescription.contains("access") {
            return .permissionError(error.localizedDescription)
        } else {
            return .unknownError(error.localizedDescription)
        }
    }
    
    private func logError(_ error: AppError) {
        print("❌ 錯誤: \(error.errorDescription ?? "未知錯誤")")
        print("💡 建議: \(error.recoverySuggestion ?? "無建議")")
        
        // 這裡可以添加更詳細的錯誤記錄
        // 例如：發送到分析服務、保存到文件等
    }
}

// MARK: - Error View

struct ErrorView: View {
    let error: AppError
    let onRetry: (() -> Void)?
    let onDismiss: (() -> Void)?
    
    init(error: AppError, onRetry: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.error = error
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // 錯誤圖示
            Image(systemName: iconForError(error))
                .font(.system(size: 60))
                .foregroundColor(colorForError(error))
            
            // 錯誤標題
            Text(titleForError(error))
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            // 錯誤描述
            Text(error.errorDescription ?? "發生未知錯誤")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // 恢復建議
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // 操作按鈕
            HStack(spacing: 16) {
                if let onRetry = onRetry {
                    Button("重試") {
                        onRetry()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                if let onDismiss = onDismiss {
                    Button("關閉") {
                        onDismiss()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 5)
    }
    
    private func iconForError(_ error: AppError) -> String {
        switch error {
        case .networkError:
            return "wifi.exclamationmark"
        case .dataError:
            return "externaldrive.badge.exclamationmark"
        case .validationError:
            return "exclamationmark.triangle"
        case .permissionError:
            return "lock.exclamationmark"
        case .unknownError:
            return "questionmark.circle"
        }
    }
    
    private func colorForError(_ error: AppError) -> Color {
        switch error {
        case .networkError:
            return .orange
        case .dataError:
            return .red
        case .validationError:
            return .yellow
        case .permissionError:
            return .purple
        case .unknownError:
            return .gray
        }
    }
    
    private func titleForError(_ error: AppError) -> String {
        switch error {
        case .networkError:
            return "網路連線問題"
        case .dataError:
            return "數據處理錯誤"
        case .validationError:
            return "數據驗證失敗"
        case .permissionError:
            return "權限不足"
        case .unknownError:
            return "未知錯誤"
        }
    }
}

// MARK: - Error Alert

struct ErrorAlert: ViewModifier {
    @Binding var error: AppError?
    let onRetry: (() -> Void)?
    
    func body(content: Content) -> some View {
        content
            .alert("錯誤", isPresented: .constant(error != nil)) {
                if let onRetry = onRetry {
                    Button("重試") {
                        onRetry()
                        error = nil
                    }
                }
                Button("確定") {
                    error = nil
                }
            } message: {
                if let error = error {
                    Text(error.errorDescription ?? "發生未知錯誤")
                }
            }
    }
}

extension View {
    func errorAlert(error: Binding<AppError?>, onRetry: (() -> Void)? = nil) -> some View {
        self.modifier(ErrorAlert(error: error, onRetry: onRetry))
    }
}

// MARK: - Loading States

enum LoadingState {
    case idle
    case loading
    case success
    case error(AppError)
}

struct ErrorLoadingView: View {
    let state: LoadingState
    let onRetry: (() -> Void)?
    
    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .loading:
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                
                Text("載入中...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        case .success:
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
                
                Text("完成")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        case .error(let error):
            ErrorView(error: error, onRetry: onRetry)
        }
    }
}

// MARK: - Retry Button

struct RetryButton: View {
    let action: () -> Void
    @State private var isRetrying = false
    
    var body: some View {
        Button {
            isRetrying = true
            action()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                isRetrying = false
            }
        } label: {
            HStack {
                if isRetrying {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text("重試")
            }
        }
        .disabled(isRetrying)
        .buttonStyle(.bordered)
    }
}

// MARK: - Error Recovery

struct ErrorRecoveryView: View {
    let error: AppError
    @State private var isRecovering = false
    
    var body: some View {
        VStack(spacing: 20) {
            ErrorView(error: error)
            
            if isRecovering {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    
                    Text("正在修復...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 12) {
                    Button("自動修復") {
                        performAutoRecovery()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("手動修復") {
                        performManualRecovery()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
    
    private func performAutoRecovery() {
        isRecovering = true
        
        // 執行自動修復邏輯
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isRecovering = false
            // 這裡可以添加修復成功的處理
        }
    }
    
    private func performManualRecovery() {
        // 顯示手動修復選項
        // 例如：重新登入、清除快取、重新安裝等
    }
}

// MARK: - Error Settings View

struct ErrorSettingsView: View {
    @StateObject private var errorHandler = ErrorHandler.shared
    
    var body: some View {
        NavigationStack {
            List {
                Section("錯誤歷史") {
                    if errorHandler.errorHistory.isEmpty {
                        Text("暫無錯誤記錄")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(errorHandler.errorHistory.reversed()) { error in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(error.errorDescription ?? "未知錯誤")
                                    .font(.headline)
                                
                                Text(error.recoverySuggestion ?? "無建議")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                Section("錯誤處理") {
                    Button("清除錯誤歷史") {
                        errorHandler.errorHistory.removeAll()
                    }
                    .foregroundColor(.red)
                    
                    Button("測試錯誤處理") {
                        errorHandler.handle(.networkError("測試錯誤"))
                    }
                }
                
                Section("自動修復") {
                    Toggle("自動重試", isOn: .constant(true))
                    Toggle("錯誤報告", isOn: .constant(true))
                    Toggle("詳細日誌", isOn: .constant(false))
                }
            }
            .navigationTitle("錯誤處理")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ErrorView(
        error: .networkError("無法連接到伺服器"),
        onRetry: { print("重試") },
        onDismiss: { print("關閉") }
    )
}
