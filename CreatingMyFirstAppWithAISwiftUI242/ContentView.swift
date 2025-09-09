//
//  ContentView.swift
//  CreatingMyFirstAppWithAISwiftUI242
//
//  Created by SHIH-YING PAN on 2025/9/9.
//

import SwiftUI
import Combine

// MARK: - Model

struct Mole: Identifiable, Equatable {
    let id = UUID()
    let index: Int
    var isUp: Bool = false
    var appearAt: Date = .distantPast
    var lifetime: TimeInterval = 1.2
}

// MARK: - ViewModel

@MainActor
final class GameViewModel: ObservableObject {
    // Grid 3x3
    static let gridSize = 3
    static let totalHoles = gridSize * gridSize

    // Published states
    @Published var moles: [Mole] = (0..<totalHoles).map { Mole(index: $0) }
    @Published var score: Int = 0
    @Published var timeRemaining: Int = 60
    @Published var isRunning: Bool = false
    @Published var isGameOver: Bool = false
    @Published var highScore: Int = UserDefaults.standard.integer(forKey: "HighScore")

    // Timing
    private var gameTimer: AnyCancellable?
    private var spawnTimer: AnyCancellable?
    private var tickInterval: TimeInterval = 0.1
    private var spawnIntervalRange: ClosedRange<Double> = 0.5...1.2
    private var moleLifetimeRange: ClosedRange<Double> = 0.9...1.6

    // Difficulty progression
    private var elapsed: TimeInterval = 0

    func start() {
        guard !isRunning else { return }
        if isGameOver {
            reset()
        }
        isRunning = true
        scheduleGameTimer()
        scheduleSpawnTimer()
    }

    func pause() {
        isRunning = false
        gameTimer?.cancel()
        spawnTimer?.cancel()
    }

    func reset() {
        score = 0
        timeRemaining = 60
        isGameOver = false
        elapsed = 0
        moles = (0..<Self.totalHoles).map { Mole(index: $0) }
    }

    func whack(hole index: Int) {
        guard isRunning else { return }
        guard let i = moles.firstIndex(where: { $0.index == index }) else { return }
        guard moles[i].isUp else { return }

        // Hit!
        moles[i].isUp = false
        score += 1
        provideHaptics(success: true)
    }

    private func scheduleGameTimer() {
        gameTimer?.cancel()
        gameTimer = Timer.publish(every: tickInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.isRunning else { return }

                self.elapsed += self.tickInterval

                // Countdown
                if Int(self.elapsed) > 0 && Int(self.elapsed * 10) % Int(1.0 / self.tickInterval) == 0 {
                    // every 1s boundary we already count below; safe no-op
                }

                // Every 1 second reduce remaining time
                // We derive by accumulating elapsed and comparing to previous whole seconds
                // Simpler: decrease by 0.1 and clamp
                if self.timeRemaining > 0 {
                    // subtract 0.1s and round to int display
                    let newTime = max(0, Double(self.timeRemaining) - self.tickInterval)
                    self.timeRemaining = Int(ceil(newTime))
                }

                // Auto hide expired moles
                let now = Date()
                for i in self.moles.indices {
                    if self.moles[i].isUp {
                        let age = now.timeIntervalSince(self.moles[i].appearAt)
                        if age >= self.moles[i].lifetime {
                            self.moles[i].isUp = false
                        }
                    }
                }

                // Difficulty ramp: every 15s shorten spawn & lifetime slightly
                let ramp = Int(self.elapsed) / 15
                let baseSpawn: ClosedRange<Double> = 0.5...1.2
                let baseLife: ClosedRange<Double> = 0.9...1.6
                let factor = max(0.7, 1.0 - Double(ramp) * 0.08)
                self.spawnIntervalRange = (baseSpawn.lowerBound * factor)...(baseSpawn.upperBound * factor)
                self.moleLifetimeRange = (baseLife.lowerBound * factor)...(baseLife.upperBound * factor)

                // Game over
                if self.timeRemaining <= 0 {
                    self.finishGame()
                }
            }
    }

    private func scheduleSpawnTimer() {
        spawnTimer?.cancel()
        let interval = Double.random(in: spawnIntervalRange)
        spawnTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.isRunning else { return }
                self.spawnOne()
                // reschedule with a new random interval
                self.scheduleSpawnTimer()
            }
    }

    private func spawnOne() {
        // choose a random hole that is currently empty
        let emptyIndices = moles.indices.filter { !moles[$0].isUp }
        guard let pick = emptyIndices.randomElement() else { return }
        var mole = moles[pick]
        mole.isUp = true
        mole.appearAt = Date()
        mole.lifetime = Double.random(in: moleLifetimeRange)
        moles[pick] = mole
    }

    private func finishGame() {
        isRunning = false
        isGameOver = true
        gameTimer?.cancel()
        spawnTimer?.cancel()
        if score > highScore {
            highScore = score
            UserDefaults.standard.set(highScore, forKey: "HighScore")
        }
        provideHaptics(success: false)
    }

    private func provideHaptics(success: Bool) {
#if os(iOS)
        if success {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        } else {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        }
#endif
    }
}

// MARK: - View

struct ContentView: View {
    @StateObject private var vm = GameViewModel()

    private let cutePink = Color(red: 1.0, green: 0.78, blue: 0.86)
    private let cutePurple = Color(red: 0.73, green: 0.67, blue: 1.0)
    private let cuteYellow = Color(red: 1.0, green: 0.92, blue: 0.6)
    private let groundBrown = Color(red: 0.63, green: 0.49, blue: 0.36)

    var body: some View {
        ZStack {
            LinearGradient(colors: [cutePink, cutePurple], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                header

                grid

                controls
            }
            .padding()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: vm.moles)
        .animation(.default, value: vm.isRunning)
        .onAppear {
            // Optional: auto-start
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("可愛的打地鼠")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text("分數：\(vm.score)  ⧗ \(vm.timeRemaining)s")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("最佳：\(vm.highScore)")
                    .font(.headline)
                    .foregroundStyle(.white)
                if vm.isGameOver {
                    Text("時間到！")
                        .font(.subheadline.bold())
                        .foregroundStyle(cuteYellow)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.25), in: Capsule())
                }
            }
        }
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: GameViewModel.gridSize)
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(vm.moles) { mole in
                HoleView(isUp: mole.isUp) {
                    vm.whack(hole: mole.index)
                }
                .accessibilityLabel(Text(mole.isUp ? "地鼠出現，點擊打擊" : "空洞"))
            }
        }
        .padding(.vertical, 8)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                vm.start()
            } label: {
                Label(vm.isRunning ? "進行中" : "開始", systemImage: "play.fill")
            }
            .buttonStyle(CapsuleButtonStyle(color: cuteYellow))
            .disabled(vm.isRunning)

            Button {
                vm.pause()
            } label: {
                Label("暫停", systemImage: "pause.fill")
            }
            .buttonStyle(CapsuleButtonStyle(color: .white.opacity(0.7)))
            .disabled(!vm.isRunning)

            Button {
                vm.reset()
            } label: {
                Label("重來", systemImage: "arrow.clockwise")
            }
            .buttonStyle(CapsuleButtonStyle(color: .white.opacity(0.4)))
        }
    }
}

// MARK: - Subviews

struct HoleView: View {
    var isUp: Bool
    var onHit: () -> Void

    private let holeColor = Color.black.opacity(0.15)
    private let rimColor = Color.black.opacity(0.08)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Hole
                Circle()
                    .fill(holeColor)
                    .overlay(
                        Circle()
                            .stroke(rimColor, lineWidth: 4)
                            .blur(radius: 1)
                            .offset(y: 2)
                            .mask(Circle())
                    )

                // Mole
                VStack(spacing: 4) {
                    // Head
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [Color(red: 0.96, green: 0.74, blue: 0.62),
                                                          Color(red: 0.86, green: 0.58, blue: 0.46)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: geo.size.width * 0.55, height: geo.size.height * 0.45)

                        // Eyes
                        HStack(spacing: 10) {
                            EyeView()
                            EyeView()
                        }
                        .offset(y: -6)

                        // Nose
                        Circle()
                            .fill(Color(red: 1.0, green: 0.6, blue: 0.7))
                            .frame(width: 14, height: 14)
                            .offset(y: 6)
                    }

                    // Paws
                    HStack(spacing: 16) {
                        PawView()
                        PawView()
                    }
                    .offset(y: -6)
                }
                .offset(y: isUp ? -geo.size.height * 0.18 : geo.size.height * 0.35)
                .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isUp)
                .onTapGesture {
                    if isUp {
                        onHit()
                    }
                }
                .accessibilityAddTraits(.isButton)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(6)
    }
}

struct EyeView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 16, height: 16)
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: 8, height: 8)
                .offset(x: 1, y: 2)
        }
    }
}

struct PawView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(red: 0.96, green: 0.74, blue: 0.62))
            .frame(width: 22, height: 12)
            .overlay(
                HStack(spacing: 3) {
                    Circle().fill(Color(red: 0.9, green: 0.6, blue: 0.5)).frame(width: 5, height: 5)
                    Circle().fill(Color(red: 0.9, green: 0.6, blue: 0.5)).frame(width: 5, height: 5)
                    Circle().fill(Color(red: 0.9, green: 0.6, blue: 0.5)).frame(width: 5, height: 5)
                }
            )
    }
}

// MARK: - Styles

struct CapsuleButtonStyle: ButtonStyle {
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundStyle(Color.black.opacity(0.8))
            .background(color, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    ContentView()
}
