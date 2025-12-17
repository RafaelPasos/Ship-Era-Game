import SwiftUI
import SpriteKit

struct ContentView: View {
    @StateObject private var playerStats = PlayerStats()
    @State private var isPaused = true
    @State private var showGameOver = false
    @State private var showWaveCleared = false

    var scene: GameScene {
        let scene = GameScene(
            size: UIScreen.main.bounds.size,
            stats: playerStats,
            gameOverAction: { showGameOver = true },
            waveClearedAction: { showWaveCleared = true },
            isPaused: $isPaused
        )
        scene.scaleMode = .aspectFill
        return scene
    }

    var body: some View {
        ZStack {
            SpriteView(scene: scene)
                .edgesIgnoringSafeArea(.all)

            if isPaused {
                VStack {
                    Text("ShipTapper")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                    Button("Start Game") {
                        scene.startGame()
                        isPaused = false
                    }
                    .font(.title)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
        }
        .sheet(isPresented: $showGameOver) {
            VStack {
                Text("Game Over")
                    .font(.largeTitle)
                Button("Play Again") {
                    showGameOver = false
                    isPaused = true
                }
                .font(.title)
                .padding()
            }
        }
        .sheet(isPresented: $showWaveCleared) {
            VStack {
                Text("Wave Cleared")
                    .font(.largeTitle)
                Button("Next Wave") {
                    showWaveCleared = false
                    scene.resumeGame()
                }
                .font(.title)
                .padding()
            }
        }
    }
}

