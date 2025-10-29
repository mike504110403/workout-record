import SwiftUI

// MARK: - Animation Extensions

extension View {
    /// 淡入動畫
    func fadeIn(duration: Double = 0.3) -> some View {
        self.opacity(0)
            .animation(.easeInOut(duration: duration), value: true)
            .onAppear {
                withAnimation(.easeInOut(duration: duration)) {
                    self.opacity(1)
                }
            }
    }
    
    /// 滑入動畫
    func slideIn(from direction: SlideDirection = .bottom, duration: Double = 0.3) -> some View {
        self.offset(offsetForDirection(direction))
            .animation(.easeOut(duration: duration), value: true)
            .onAppear {
                withAnimation(.easeOut(duration: duration)) {
                    self.offset(.zero)
                }
            }
    }
    
    /// 縮放動畫
    func scaleIn(duration: Double = 0.3) -> some View {
        self.scaleEffect(0.8)
            .opacity(0)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: true)
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    self.scaleEffect(1.0)
                    self.opacity(1)
                }
            }
    }
    
    /// 成就解鎖動畫
    func achievementUnlock() -> some View {
        self.scaleEffect(0.5)
            .opacity(0)
            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: true)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    self.scaleEffect(1.1)
                    self.opacity(1)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.scaleEffect(1.0)
                    }
                }
            }
    }
    
    /// 按鈕點擊動畫
    func buttonPress() -> some View {
        self.scaleEffect(1.0)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.1)) {
                    self.scaleEffect(0.95)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        self.scaleEffect(1.0)
                    }
                }
            }
    }
    
    /// 載入動畫
    func loadingPulse() -> some View {
        self.opacity(0.5)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: true)
    }
    
    private func offsetForDirection(_ direction: SlideDirection) -> CGSize {
        switch direction {
        case .top:
            return CGSize(width: 0, height: -50)
        case .bottom:
            return CGSize(width: 0, height: 50)
        case .left:
            return CGSize(width: -50, height: 0)
        case .right:
            return CGSize(width: 50, height: 0)
        }
    }
}

enum SlideDirection {
    case top, bottom, left, right
}

// MARK: - Custom Animations

struct BounceAnimation: ViewModifier {
    @State private var isAnimating = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isAnimating ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear {
                isAnimating = true
            }
    }
}

struct ShakeAnimation: ViewModifier {
    @State private var isShaking = false
    
    func body(content: Content) -> some View {
        content
            .offset(x: isShaking ? -5 : 5)
            .animation(.easeInOut(duration: 0.1).repeatCount(6, autoreverses: true), value: isShaking)
    }
    
    func shake() {
        isShaking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            isShaking = false
        }
    }
}

struct ProgressAnimation: ViewModifier {
    let progress: Double
    @State private var animatedProgress: Double = 0
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                withAnimation(.easeOut(duration: 1.0)) {
                    animatedProgress = progress
                }
            }
            .onChange(of: progress) { _, newValue in
                withAnimation(.easeOut(duration: 0.5)) {
                    animatedProgress = newValue
                }
            }
    }
}

// MARK: - View Extensions

extension View {
    func bounce() -> some View {
        self.modifier(BounceAnimation())
    }
    
    func shake() -> some View {
        self.modifier(ShakeAnimation())
    }
    
    func progressAnimation(_ progress: Double) -> some View {
        self.modifier(ProgressAnimation(progress: progress))
    }
}

// MARK: - Card Animations

struct CardFlipAnimation: ViewModifier {
    @State private var isFlipped = false
    let duration: Double
    
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(isFlipped ? 180 : 0),
                axis: (x: 0, y: 1, z: 0)
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: duration)) {
                    isFlipped.toggle()
                }
            }
    }
}

extension View {
    func cardFlip(duration: Double = 0.6) -> some View {
        self.modifier(CardFlipAnimation(duration: duration))
    }
}

// MARK: - Loading Animations

struct LoadingDots: View {
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
        }
    }
}

struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.05 : 1.0)
            .opacity(isPulsing ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear {
                isPulsing = true
            }
    }
}

extension View {
    func pulse() -> some View {
        self.modifier(PulseAnimation())
    }
}

// MARK: - Success Animation

struct SuccessCheckmark: View {
    @State private var trimEnd: CGFloat = 0
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.green, lineWidth: 3)
                .frame(width: 50, height: 50)
            
            Path { path in
                path.move(to: CGPoint(x: 15, y: 25))
                path.addLine(to: CGPoint(x: 22, y: 32))
                path.addLine(to: CGPoint(x: 35, y: 18))
            }
            .trim(from: 0, to: trimEnd)
            .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .frame(width: 50, height: 50)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8)) {
                trimEnd = 1.0
            }
        }
    }
}
