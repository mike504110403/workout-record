import SwiftUI

// MARK: - 鍵盤關閉擴展

extension View {
    /// 點擊畫面時隱藏鍵盤（適用於表單視圖）
    func dismissKeyboardOnInteraction() -> some View {
        self.modifier(DismissKeyboardModifier())
    }
}

/// 智能鍵盤關閉修飾符
/// 使用 Toolbar 加入「完成」按鈕，不會干擾其他互動元素
struct DismissKeyboardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        hideKeyboard()
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

