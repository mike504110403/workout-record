import SwiftUI

/// 統一的搜尋欄組件
struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "搜尋..."
    var onSearchButtonClicked: (() -> Void)? = nil
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: $text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit {
                    onSearchButtonClicked?()
                }
            
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

#Preview {
    @State var searchText = ""
    return SearchBar(text: $searchText, placeholder: "搜尋動作...")
        .padding()
}
