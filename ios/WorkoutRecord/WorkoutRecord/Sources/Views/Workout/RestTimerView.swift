import SwiftUI
import Combine

struct RestTimerView: View {
    @StateObject private var timerManager = RestTimerManager()
    @Environment(\.dismiss) var dismiss
    
    let initialSeconds: Int
    let exerciseName: String
    
    init(seconds: Int, exerciseName: String) {
        self.initialSeconds = seconds
        self.exerciseName = exerciseName
    }
    
    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.9)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Exercise name
                Text(exerciseName)
                    .font(.title3)
                    .foregroundColor(.white)
                
                // Timer display
                ZStack {
                    // Progress ring
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 12)
                    
                    Circle()
                        .trim(from: 0, to: timerManager.progress)
                        .stroke(
                            timerColor,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.5), value: timerManager.progress)
                    
                    // Time text
                    VStack(spacing: 8) {
                        Text(timeString)
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("秒")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .frame(width: 280, height: 280)
                
                // Controls
                HStack(spacing: 40) {
                    // Decrease 15s
                    Button {
                        timerManager.adjustTime(by: -15)
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 40))
                            Text("-15s")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                    }
                    
                    // Play/Pause
                    Button {
                        if timerManager.isRunning {
                            timerManager.pause()
                        } else {
                            timerManager.start()
                        }
                    } label: {
                        Image(systemName: timerManager.isRunning ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.white)
                    }
                    
                    // Increase 15s
                    Button {
                        timerManager.adjustTime(by: 15)
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 40))
                            Text("+15s")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                    }
                }
                
                // Skip button
                Button {
                    dismiss()
                } label: {
                    Text("跳過休息")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
            }
        }
        .onAppear {
            timerManager.setup(seconds: initialSeconds)
            timerManager.start()
        }
        .onDisappear {
            timerManager.stop()
        }
        .onChange(of: timerManager.remainingSeconds) { newValue in
            if newValue <= 0 {
                // Timer finished
                timerManager.playCompletionSound()
                dismiss()
            }
        }
    }
    
    private var timeString: String {
        let minutes = timerManager.remainingSeconds / 60
        let seconds = timerManager.remainingSeconds % 60
        
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "%d", seconds)
        }
    }
    
    private var timerColor: Color {
        if timerManager.remainingSeconds <= 10 {
            return .red
        } else if timerManager.remainingSeconds <= 30 {
            return .orange
        } else {
            return .green
        }
    }
}

// MARK: - Rest Timer Manager
@MainActor
class RestTimerManager: ObservableObject {
    @Published var remainingSeconds: Int = 0
    @Published var totalSeconds: Int = 0
    @Published var isRunning: Bool = false
    @Published var exerciseName: String?
    
    private var timer: Timer?
    
    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(remainingSeconds) / Double(totalSeconds)
    }
    
    func setup(seconds: Int, exerciseName: String? = nil) {
        self.totalSeconds = seconds
        self.remainingSeconds = seconds
        self.exerciseName = exerciseName
    }
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if self.remainingSeconds > 0 {
                    self.remainingSeconds -= 1
                } else {
                    self.stop()
                }
            }
        }
    }
    
    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }
    
    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }
    
    func adjustTime(by seconds: Int) {
        remainingSeconds = max(0, remainingSeconds + seconds)
        totalSeconds = max(totalSeconds, remainingSeconds)
    }
    
    func playCompletionSound() {
        // TODO: Play system sound or haptic feedback
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }
    
    deinit {
        timer?.invalidate()
    }
}

// MARK: - Rest Timer Header View (Compact)
struct RestTimerHeaderView: View {
    @ObservedObject var timerManager: RestTimerManager
    
    var body: some View {
        HStack(spacing: 12) {
            // 時間顯示
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .foregroundColor(timerColor)
                Text(timeString)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(timerColor)
            }
            
            // 動作名稱
            if let exerciseName = timerManager.exerciseName {
                Text(exerciseName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 快進按鈕
            Button {
                timerManager.stop()
                timerManager.remainingSeconds = 0
            } label: {
                Image(systemName: "forward.fill")
                    .font(.body)
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(
            ZStack {
                Color(.systemBackground)
                
                // 進度條
                GeometryReader { geometry in
                    Rectangle()
                        .fill(timerColor.opacity(0.2))
                        .frame(width: geometry.size.width * timerManager.progress)
                }
            }
        )
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var timeString: String {
        let minutes = timerManager.remainingSeconds / 60
        let seconds = timerManager.remainingSeconds % 60
        
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
    
    private var timerColor: Color {
        if timerManager.remainingSeconds <= 10 {
            return .red
        } else if timerManager.remainingSeconds <= 30 {
            return .orange
        } else {
            return .green
        }
    }
}

#Preview {
    RestTimerView(seconds: 90, exerciseName: "槓鈴臥推")
}

#Preview("Header") {
    @StateObject var manager = RestTimerManager()
    RestTimerHeaderView(timerManager: manager)
        .onAppear {
            manager.setup(seconds: 90, exerciseName: "槓鈴臥推")
            manager.start()
        }
}

