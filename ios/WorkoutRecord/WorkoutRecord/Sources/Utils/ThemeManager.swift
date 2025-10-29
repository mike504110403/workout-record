import SwiftUI
import Combine

// MARK: - Theme Manager

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @Published var isDarkMode: Bool = false
    @Published var accentColor: Color = .blue
    @Published var customColors: [String: Color] = [:]
    
    private init() {
        loadThemeSettings()
    }
    
    // MARK: - Color Schemes
    
    var primaryColor: Color {
        isDarkMode ? .white : .black
    }
    
    var secondaryColor: Color {
        isDarkMode ? .gray : .secondary
    }
    
    var backgroundColor: Color {
        isDarkMode ? Color(.systemBackground) : Color(.systemBackground)
    }
    
    var cardBackgroundColor: Color {
        isDarkMode ? Color(.secondarySystemBackground) : Color(.systemBackground)
    }
    
    var borderColor: Color {
        isDarkMode ? Color(.separator) : Color(.separator)
    }
    
    // MARK: - Custom Colors
    
    func setCustomColor(_ color: Color, for key: String) {
        customColors[key] = color
        saveThemeSettings()
    }
    
    func getCustomColor(for key: String) -> Color {
        customColors[key] ?? accentColor
    }
    
    // MARK: - Theme Settings
    
    func toggleDarkMode() {
        isDarkMode.toggle()
        saveThemeSettings()
    }
    
    func setAccentColor(_ color: Color) {
        accentColor = color
        saveThemeSettings()
    }
    
    private func loadThemeSettings() {
        isDarkMode = UserDefaults.standard.bool(forKey: "isDarkMode")
        
        if let colorData = UserDefaults.standard.data(forKey: "accentColor"),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: colorData) {
            accentColor = Color(color)
        }
    }
    
    private func saveThemeSettings() {
        UserDefaults.standard.set(isDarkMode, forKey: "isDarkMode")
        
        if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: UIColor(accentColor), requiringSecureCoding: false) {
            UserDefaults.standard.set(colorData, forKey: "accentColor")
        }
    }
}

// MARK: - Color Extensions

extension Color {
    // MARK: - App Colors
    
    static let appPrimary = Color("AppPrimary")
    static let appSecondary = Color("AppSecondary")
    static let appAccent = Color("AppAccent")
    
    // MARK: - Semantic Colors
    
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
    static let info = Color.blue
    
    // MARK: - Workout Colors
    
    static let workoutCard = Color("WorkoutCard")
    static let exerciseCard = Color("ExerciseCard")
    static let statsCard = Color("StatsCard")
    
    // MARK: - Dynamic Colors
    
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor(dark)
            default:
                return UIColor(light)
            }
        })
    }
}

// MARK: - Theme View Modifiers

struct ThemedBackground: ViewModifier {
    @EnvironmentObject private var themeManager: ThemeManager
    
    func body(content: Content) -> some View {
        content
            .background(themeManager.backgroundColor)
    }
}

struct ThemedCard: ViewModifier {
    @EnvironmentObject private var themeManager: ThemeManager
    
    func body(content: Content) -> some View {
        content
            .background(themeManager.cardBackgroundColor)
            .cornerRadius(12)
            .shadow(color: .black.opacity(themeManager.isDarkMode ? 0.3 : 0.1), radius: 5, x: 0, y: 2)
    }
}

struct ThemedText: ViewModifier {
    @EnvironmentObject private var themeManager: ThemeManager
    let style: TextStyle
    
    enum TextStyle {
        case primary, secondary, accent, success, warning, error
    }
    
    func body(content: Content) -> some View {
        content
            .foregroundColor(colorForStyle(style))
    }
    
    private func colorForStyle(_ style: TextStyle) -> Color {
        switch style {
        case .primary:
            return themeManager.primaryColor
        case .secondary:
            return themeManager.secondaryColor
        case .accent:
            return themeManager.accentColor
        case .success:
            return .success
        case .warning:
            return .warning
        case .error:
            return .error
        }
    }
}

// MARK: - View Extensions

extension View {
    func themedBackground() -> some View {
        self.modifier(ThemedBackground())
    }
    
    func themedCard() -> some View {
        self.modifier(ThemedCard())
    }
    
    func themedText(_ style: ThemedText.TextStyle = .primary) -> some View {
        self.modifier(ThemedText(style: style))
    }
}

// MARK: - Theme Settings View

struct ThemeSettingsView: View {
    @StateObject private var themeManager = ThemeManager.shared
    @State private var showingColorPicker = false
    
    private let accentColors: [Color] = [
        .blue, .green, .orange, .red, .purple, .pink, .indigo, .cyan
    ]
    
    var body: some View {
        NavigationStack {
            List {
                Section("外觀設定") {
                    Toggle("深色模式", isOn: $themeManager.isDarkMode)
                        .onChange(of: themeManager.isDarkMode) { _, _ in
                            themeManager.toggleDarkMode()
                        }
                }
                
                Section("主題色彩") {
                    HStack {
                        Text("強調色")
                        Spacer()
                        Circle()
                            .fill(themeManager.accentColor)
                            .frame(width: 30, height: 30)
                            .onTapGesture {
                                showingColorPicker = true
                            }
                    }
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                        ForEach(accentColors, id: \.self) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .stroke(themeManager.accentColor == color ? Color.primary : Color.clear, lineWidth: 3)
                                )
                                .onTapGesture {
                                    themeManager.setAccentColor(color)
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section("預覽") {
                    VStack(spacing: 16) {
                        // 卡片預覽
                        VStack(alignment: .leading, spacing: 8) {
                            Text("預覽卡片")
                                .font(.headline)
                                .themedText(.primary)
                            
                            Text("這是主題預覽")
                                .font(.body)
                                .themedText(.secondary)
                            
                            HStack {
                                Text("強調色")
                                    .themedText(.accent)
                                
                                Spacer()
                                
                                Text("成功")
                                    .themedText(.success)
                            }
                        }
                        .padding()
                        .themedCard()
                        
                        // 按鈕預覽
                        HStack {
                            Button("主要按鈕") { }
                                .buttonStyle(.borderedProminent)
                                .tint(themeManager.accentColor)
                            
                            Button("次要按鈕") { }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("主題設定")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingColorPicker) {
                ColorPickerView(selectedColor: $themeManager.accentColor)
            }
        }
        .environmentObject(themeManager)
    }
}

struct ColorPickerView: View {
    @Binding var selectedColor: Color
    @Environment(\.dismiss) private var dismiss
    
    private let colors: [Color] = [
        .red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue,
        .indigo, .purple, .pink, .brown, .gray, .black, .white
    ]
    
    var body: some View {
        NavigationStack {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                ForEach(colors, id: \.self) { color in
                    Circle()
                        .fill(color)
                        .frame(width: 50, height: 50)
                        .overlay(
                            Circle()
                                .stroke(selectedColor == color ? Color.primary : Color.clear, lineWidth: 3)
                        )
                        .onTapGesture {
                            selectedColor = color
                        }
                }
            }
            .padding()
            .navigationTitle("選擇顏色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ThemeSettingsView()
}
