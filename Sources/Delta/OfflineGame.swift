import AppKit
import SwiftUI

private struct DinoObstacle {
    var x: CGFloat
    var isFlying: Bool
}

struct OfflineGameView: View {
    @AppStorage("delta.dinoBest") private var bestScore = 0
    @State private var score = 0
    @State private var dinoY: CGFloat = 0
    @State private var velocity: CGFloat = 0
    @State private var crouching = false
    @State private var obstacles: [DinoObstacle] = [DinoObstacle(x: 680, isFlying: false)]
    @State private var speed: CGFloat = 5
    @State private var gameOver = false

    private let tick = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white
                Canvas { context, size in
                    let floor = size.height * 0.72
                    var ground = Path()
                    ground.move(to: CGPoint(x: 0, y: floor))
                    ground.addLine(to: CGPoint(x: size.width, y: floor))
                    context.stroke(ground, with: .color(.gray.opacity(0.8)), lineWidth: 2)

                    let dinoHeight: CGFloat = crouching ? 28 : 42
                    let dino = CGRect(x: 80, y: floor - dinoHeight - dinoY, width: 28, height: dinoHeight)
                    context.fill(Path(roundedRect: dino, cornerRadius: 5), with: .color(Color(red: 0.16, green: 0.22, blue: 0.19)))
                    context.fill(Path(ellipseIn: CGRect(x: 98, y: dino.minY + 2, width: 21, height: 20)),
                                 with: .color(Color(red: 0.16, green: 0.22, blue: 0.19)))
                    context.fill(Path(ellipseIn: CGRect(x: 112, y: dino.minY + 8, width: 3, height: 3)),
                                 with: .color(.white))
                    for obstacle in obstacles {
                        if obstacle.isFlying {
                            let body = CGRect(x: obstacle.x, y: floor - 48, width: 30, height: 16)
                            context.fill(Path(roundedRect: body, cornerRadius: 8),
                                         with: .color(Color(red: 0.35, green: 0.31, blue: 0.26)))
                            context.fill(Path(ellipseIn: CGRect(x: obstacle.x + 17, y: floor - 54, width: 16, height: 12)),
                                         with: .color(Color(red: 0.35, green: 0.31, blue: 0.26)))
                        } else {
                            let cactus = CGRect(x: obstacle.x, y: floor - 35, width: 20, height: 35)
                            context.fill(Path(roundedRect: cactus, cornerRadius: 3),
                                         with: .color(Color(red: 0.20, green: 0.37, blue: 0.27)))
                            context.fill(Path(roundedRect: CGRect(x: obstacle.x - 7, y: floor - 26, width: 8, height: 6), cornerRadius: 2),
                                         with: .color(Color(red: 0.20, green: 0.37, blue: 0.27)))
                        }
                    }
                    for index in 0..<12 {
                        let x = CGFloat(index) * (size.width / 11)
                        context.fill(Path(ellipseIn: CGRect(x: x, y: floor + 11 + CGFloat(index % 3) * 5, width: 3, height: 2)),
                                     with: .color(.gray.opacity(0.25)))
                    }
                }
                VStack {
                    HStack {
                        Text("НЕТ ПОДКЛЮЧЕНИЯ К ИНТЕРНЕТУ")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .tracking(1.2)
                        Spacer()
                        Text("СЧЁТ  \(score)    РЕКОРД  \(bestScore)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    Spacer()
                    if gameOver {
                        VStack(spacing: 12) {
                            Text("Игра окончена").font(.title2.bold())
                            Button(action: restart) {
                                Label("Играть снова", systemImage: "arrow.clockwise")
                                    .padding(.horizontal, 18).padding(.vertical, 10)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.bottom, 80)
                    } else {
                        Text("Пробел или ↑ — прыгнуть · ↓ — пригнуться")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 22)
                    }
                }
                GameInputView(onKeyDown: keyDown, onKeyUp: keyUp)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(8)
            }
            .onReceive(tick) { _ in update(size: proxy.size) }
            .onAppear { gameOver = false }
        }
    }

    private func update(size: CGSize) {
        guard !gameOver else { return }
        if dinoY > 0 || velocity > 0 {
            dinoY += velocity
            velocity -= 0.8
            if dinoY <= 0 { dinoY = 0; velocity = 0 }
        }
        obstacles = obstacles.map { DinoObstacle(x: $0.x - speed, isFlying: $0.isFlying) }.filter { $0.x > -40 }
        if let last = obstacles.last, last.x < size.width - CGFloat.random(in: 230...390) {
            obstacles.append(DinoObstacle(
                x: size.width + CGFloat.random(in: 30...170),
                isFlying: score > 120 && Int.random(in: 0...3) == 0
            ))
        }
        if obstacles.isEmpty { obstacles = [DinoObstacle(x: size.width + 80, isFlying: false)] }
        score += 1
        if score % 250 == 0 { speed = min(speed + 0.7, 13) }
        let dinoRight: CGFloat = 108
        let hit = obstacles.contains { obstacle in
            let width: CGFloat = obstacle.isFlying ? 30 : 20
            guard obstacle.x < dinoRight && obstacle.x + width > 80 else { return false }
            if obstacle.isFlying { return !crouching && dinoY < 28 }
            return dinoY < (crouching ? 28 : 38)
        }
        if hit {
            gameOver = true
            bestScore = max(bestScore, score)
        }
    }

    private func keyDown(_ key: UInt16) {
        switch key {
        case 49, 126:
            if dinoY == 0 && !gameOver {
                velocity = 12
                crouching = false
            }
            if gameOver { restart() }
        case 125:
            crouching = true
        default: break
        }
    }

    private func keyUp(_ key: UInt16) {
        if key == 125 { crouching = false }
    }

    private func restart() {
        score = 0
        dinoY = 0
        velocity = 0
        speed = 5
        obstacles = [DinoObstacle(x: 700, isFlying: false)]
        gameOver = false
    }
}

private struct GameInputView: NSViewRepresentable {
    var onKeyDown: (UInt16) -> Void
    var onKeyUp: (UInt16) -> Void

    func makeNSView(context: Context) -> GameKeyView {
        let view = GameKeyView()
        view.onKeyDown = onKeyDown
        view.onKeyUp = onKeyUp
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ view: GameKeyView, context: Context) {
        view.onKeyDown = onKeyDown
        view.onKeyUp = onKeyUp
    }
}

private final class GameKeyView: NSView {
    var onKeyDown: ((UInt16) -> Void)?
    var onKeyUp: ((UInt16) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
    override func keyDown(with event: NSEvent) { onKeyDown?(event.keyCode) }
    override func keyUp(with event: NSEvent) { onKeyUp?(event.keyCode) }
}
