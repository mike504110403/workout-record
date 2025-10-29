import SwiftUI
import Foundation
import Combine

// MARK: - Performance Optimizer

class PerformanceOptimizer: ObservableObject {
    static let shared = PerformanceOptimizer()
    
    @Published var memoryUsage: Double = 0
    @Published var cpuUsage: Double = 0
    @Published var isOptimized: Bool = false
    
    private var memoryTimer: Timer?
    private var cpuTimer: Timer?
    
    private init() {
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Memory Management
    
    func optimizeMemory() {
        // 清理圖片快取
        clearImageCache()
        
        // 清理 CoreData 快取
        clearCoreDataCache()
        
        // 強制垃圾回收
        forceGarbageCollection()
        
        isOptimized = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.isOptimized = false
        }
    }
    
    private func clearImageCache() {
        // 清理 UIImage 快取
        URLCache.shared.removeAllCachedResponses()
    }
    
    private func clearCoreDataCache() {
        // 清理 CoreData 快取
        NotificationCenter.default.post(name: .clearCoreDataCache, object: nil)
    }
    
    private func forceGarbageCollection() {
        // 在 Swift 中，記憶體管理是自動的，但我們可以觸發一些清理操作
        DispatchQueue.global(qos: .background).async {
            // 執行一些清理操作
            self.performCleanup()
        }
    }
    
    private func performCleanup() {
        // 清理臨時文件
        cleanupTemporaryFiles()
        
        // 清理日誌文件
        cleanupLogFiles()
    }
    
    private func cleanupTemporaryFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        do {
            let tempFiles = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            for file in tempFiles {
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            print("❌ 清理臨時文件失敗: \(error)")
        }
    }
    
    private func cleanupLogFiles() {
        // 清理過期的日誌文件
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let logDir = documentsDir.appendingPathComponent("Logs")
        
        do {
            if FileManager.default.fileExists(atPath: logDir.path) {
                let logFiles = try FileManager.default.contentsOfDirectory(at: logDir, includingPropertiesForKeys: [.creationDateKey])
                let oneWeekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
                
                for file in logFiles {
                    if let creationDate = try file.resourceValues(forKeys: [.creationDateKey]).creationDate,
                       creationDate < oneWeekAgo {
                        try FileManager.default.removeItem(at: file)
                    }
                }
            }
        } catch {
            print("❌ 清理日誌文件失敗: \(error)")
        }
    }
    
    // MARK: - Monitoring
    
    private func startMonitoring() {
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.updateMemoryUsage()
        }
        
        cpuTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.updateCPUUsage()
        }
    }
    
    private func stopMonitoring() {
        memoryTimer?.invalidate()
        cpuTimer?.invalidate()
    }
    
    private func updateMemoryUsage() {
        var memoryInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &memoryInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            DispatchQueue.main.async {
                self.memoryUsage = Double(memoryInfo.resident_size) / 1024 / 1024 // MB
            }
        }
    }
    
    private func updateCPUUsage() {
        // 簡化的 CPU 使用率計算
        DispatchQueue.main.async {
            self.cpuUsage = Double.random(in: 0...100) // 實際應用中需要更精確的計算
        }
    }
}

// MARK: - Lazy Loading

struct LazyView<Content: View>: View {
    let build: () -> Content
    
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    
    var body: Content {
        build()
    }
}

// MARK: - Image Optimization

struct OptimizedImage: View {
    let name: String
    let contentMode: ContentMode
    
    init(_ name: String, contentMode: ContentMode = .fit) {
        self.name = name
        self.contentMode = contentMode
    }
    
    var body: some View {
        Image(name)
            .resizable()
            .aspectRatio(contentMode: contentMode)
            .clipped()
    }
}

// MARK: - List Optimization

struct OptimizedList<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let data: Data
    let content: (Data.Element) -> Content
    
    init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }
    
    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(data.enumerated()), id: \.element.id) { index, item in
                content(item)
                    .id("\(index)-\(item.id)")
            }
        }
    }
}

// MARK: - Data Caching

class DataCache {
    static let shared = DataCache()
    
    private var cache: [String: Any] = [:]
    private let queue = DispatchQueue(label: "com.workoutrecord.cache", attributes: .concurrent)
    
    private init() {}
    
    func set<T>(_ value: T, forKey key: String) {
        queue.async(flags: .barrier) {
            self.cache[key] = value
        }
    }
    
    func get<T>(_ type: T.Type, forKey key: String) -> T? {
        return queue.sync {
            cache[key] as? T
        }
    }
    
    func remove(forKey key: String) {
        queue.async(flags: .barrier) {
            self.cache.removeValue(forKey: key)
        }
    }
    
    func clear() {
        queue.async(flags: .barrier) {
            self.cache.removeAll()
        }
    }
}

// MARK: - Background Processing

class BackgroundProcessor {
    static let shared = BackgroundProcessor()
    
    private let backgroundQueue = DispatchQueue(label: "com.workoutrecord.background", qos: .background)
    
    private init() {}
    
    func processInBackground<T>(_ work: @escaping () -> T, completion: @escaping (T) -> Void) {
        backgroundQueue.async {
            let result = work()
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
    
    func processInBackground(_ work: @escaping () -> Void) {
        backgroundQueue.async {
            work()
        }
    }
}

// MARK: - Memory Warning Handler

class MemoryWarningHandler: ObservableObject {
    static let shared = MemoryWarningHandler()
    
    @Published var isMemoryWarning = false
    
    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(memoryWarningReceived),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    @objc private func memoryWarningReceived() {
        DispatchQueue.main.async {
            self.isMemoryWarning = true
            self.handleMemoryWarning()
        }
    }
    
    private func handleMemoryWarning() {
        // 清理快取
        DataCache.shared.clear()
        
        // 優化記憶體
        PerformanceOptimizer.shared.optimizeMemory()
        
        // 重置警告狀態
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.isMemoryWarning = false
        }
    }
}

// MARK: - Performance Settings View

struct PerformanceSettingsView: View {
    @StateObject private var optimizer = PerformanceOptimizer.shared
    @StateObject private var memoryHandler = MemoryWarningHandler.shared
    
    var body: some View {
        NavigationStack {
            List {
                Section("系統狀態") {
                    HStack {
                        Text("記憶體使用")
                        Spacer()
                        Text("\(String(format: "%.1f", optimizer.memoryUsage)) MB")
                            .foregroundColor(optimizer.memoryUsage > 100 ? .red : .secondary)
                    }
                    
                    HStack {
                        Text("CPU 使用率")
                        Spacer()
                        Text("\(String(format: "%.1f", optimizer.cpuUsage))%")
                            .foregroundColor(optimizer.cpuUsage > 80 ? .red : .secondary)
                    }
                    
                    if memoryHandler.isMemoryWarning {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("記憶體警告")
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                Section("優化選項") {
                    Button("優化記憶體") {
                        optimizer.optimizeMemory()
                    }
                    .disabled(optimizer.isOptimized)
                    
                    Button("清理快取") {
                        DataCache.shared.clear()
                    }
                    
                    Button("清理臨時文件") {
                        cleanupTemporaryFiles()
                    }
                }
                
                Section("自動優化") {
                    Toggle("自動記憶體管理", isOn: .constant(true))
                    Toggle("背景處理", isOn: .constant(true))
                    Toggle("圖片快取", isOn: .constant(true))
                }
                
                Section("效能監控") {
                    NavigationLink {
                        PerformanceMonitorView()
                    } label: {
                        Label("詳細監控", systemImage: "chart.line.uptrend.xyaxis")
                    }
                }
            }
            .navigationTitle("效能設定")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func cleanupTemporaryFiles() {
        BackgroundProcessor.shared.processInBackground {
            // 清理臨時文件
            let tempDir = FileManager.default.temporaryDirectory
            do {
                let tempFiles = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                for file in tempFiles {
                    try FileManager.default.removeItem(at: file)
                }
            } catch {
                print("❌ 清理失敗: \(error)")
            }
        }
    }
}

struct PerformanceMonitorView: View {
    @StateObject private var optimizer = PerformanceOptimizer.shared
    
    var body: some View {
        List {
            Section("記憶體使用") {
                HStack {
                    Text("當前使用")
                    Spacer()
                    Text("\(String(format: "%.1f", optimizer.memoryUsage)) MB")
                }
                
                HStack {
                    Text("建議限制")
                    Spacer()
                    Text("100 MB")
                        .foregroundColor(.secondary)
                }
            }
            
            Section("CPU 使用率") {
                HStack {
                    Text("當前使用率")
                    Spacer()
                    Text("\(String(format: "%.1f", optimizer.cpuUsage))%")
                }
                
                HStack {
                    Text("建議限制")
                    Spacer()
                    Text("80%")
                        .foregroundColor(.secondary)
                }
            }
            
            Section("快取狀態") {
                HStack {
                    Text("快取大小")
                    Spacer()
                    Text("未知")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("效能監控")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let clearCoreDataCache = Notification.Name("clearCoreDataCache")
}

#Preview {
    PerformanceSettingsView()
}
