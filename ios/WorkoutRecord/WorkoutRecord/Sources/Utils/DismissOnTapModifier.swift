import SwiftUI

/// 點擊外部區域關閉彈窗的 ViewModifier
struct DismissOnTapModifier: ViewModifier {
    let onDismiss: () -> Void
    
    func body(content: Content) -> some View {
        content
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onDismiss()
                    }
            )
    }
}

/// 點擊外部區域關閉彈窗的 ViewModifier（用於 Sheet）
struct DismissOnTapSheetModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    let onDismiss: (() -> Void)?
    
    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let onDismiss = onDismiss {
                            onDismiss()
                        } else {
                            dismiss()
                        }
                    }
            )
    }
}

/// 點擊外部區域關閉彈窗的 ViewModifier（用於 Alert）
struct DismissOnTapAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    
    init(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil) {
        self._isPresented = isPresented
        self.onDismiss = onDismiss
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isPresented = false
                        onDismiss?()
                    }
            )
    }
}

// MARK: - View Extensions
extension View {
    /// 添加點擊外部區域關閉功能（用於 Sheet）
    func dismissOnTapSheet(onDismiss: (() -> Void)? = nil) -> some View {
        self.modifier(DismissOnTapSheetModifier(onDismiss: onDismiss))
    }
    
    /// 添加點擊外部區域關閉功能（用於 Alert）
    func dismissOnTapAlert(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil) -> some View {
        self.modifier(DismissOnTapAlertModifier(isPresented: isPresented, onDismiss: onDismiss))
    }
    
    /// 添加點擊外部區域關閉功能（通用）
    func dismissOnTap(onDismiss: @escaping () -> Void) -> some View {
        self.modifier(DismissOnTapModifier(onDismiss: onDismiss))
    }
}
