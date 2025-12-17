import SwiftUI
import SpriteKit
import AVFoundation

// MARK: - Core Enums & Structs
enum GameScreen { case mainMenu, game, store, gameOver, pause }

class PlayerStats: ObservableObject {
    @Published var gold: Int = 0
    @Published var maxHP: Int = 300
    @Published var currentHP: Int = 300
    @Published var maxShield: Int = 300
    @Published var currentShield: Int = 0
    @Published var minDamageMultiplier: Double = 0.20
    @Published var baseShipSpeed: CGFloat = 1.5
    @Published var baseReloadSpeed: Double = 3.0
    @Published var cannonCount: Int = 1
    enum CannonballType: String, CaseIterable { case standard = "Standard Shot", hollow = "Hollow Ball" }
    @Published var currentCannonball: CannonballType = .standard
    @Published var critChance: Double = 0.10
    @Published var critDamageMultiplier: Double = 1.25

    enum UpgradeType { case minDamage, shipSpeed, reloadSpeed, cannonCount, cannonballType, critChance, critDamage, repair }
    
    func getCannonballDamage() -> Int {
        switch currentCannonball {
        case .standard: return 50
        case .hollow: return 85
        }
    }
    
    func apply(upgrade: Upgrade) {
        guard gold >= upgrade.cost else { return }
        gold -= upgrade.cost
        
        switch upgrade.type {
        case .minDamage: minDamageMultiplier += upgrade.value
        case .shipSpeed: baseShipSpeed += upgrade.value
        case .reloadSpeed: baseReloadSpeed -= upgrade.value
        case .cannonCount: cannonCount += Int(upgrade.value)
        case .critChance: critChance += upgrade.value
        case .critDamage: critDamageMultiplier += upgrade.value
        case .cannonballType:
            if let ballType = upgrade.payload as? CannonballType { currentCannonball = ballType }
        case .repair: break
        }
    }
}

struct Upgrade {
    let id = UUID()
    let name: String
    let description: String
    let cost: Int
    let type: PlayerStats.UpgradeType
    let value: Double
    let payload: Any?
    var condition: ((PlayerStats) -> Bool)?
    init(name: String, description: String, cost: Int, type: PlayerStats.UpgradeType, value: Double, payload: Any? = nil, condition: ((PlayerStats) -> Bool)? = nil) {
        self.name = name; self.description = description; self.cost = cost; self.type = type; self.value = value; self.payload = payload; self.condition = condition
    }
}

// MARK: - SwiftUI Views

struct StoreView: View {
    @ObservedObject var playerStats: PlayerStats
    var onExitStore: () -> Void
    var onRepair: () -> Void

    let gunneryUpgrades: [Upgrade] = [
        Upgrade(name: "Improve Ballast", description: "+5% Min. Damage", cost: 300, type: .minDamage, value: 0.05, condition: { $0.minDamageMultiplier < 0.3 }),
        Upgrade(name: "Gunnery Tables", description: "+7% Min. Damage", cost: 700, type: .minDamage, value: 0.07, condition: { $0.minDamageMultiplier >= 0.3 && $0.minDamageMultiplier < 0.45 }),
        Upgrade(name: "Spot Weakness", description: "+2% Crit Chance", cost: 450, type: .critChance, value: 0.02, condition: { $0.critChance < 0.15 }),
        Upgrade(name: "Heavier Shot", description: "+15% Crit Damage", cost: 600, type: .critDamage, value: 0.15, condition: { $0.critDamageMultiplier < 1.45 }),
    ]
    let shipyardUpgrades: [Upgrade] = [
        Upgrade(name: "Streamline Hull", description: "+0.2 Ship Speed", cost: 300, type: .shipSpeed, value: 0.2, condition: { $0.baseShipSpeed < 2.2 }),
        Upgrade(name: "Larger Sails", description: "+0.3 Ship Speed", cost: 750, type: .shipSpeed, value: 0.3, condition: { $0.baseShipSpeed >= 2.2 && $0.baseShipSpeed < 2.5 })
    ]
    let ordnanceUpgrades: [Upgrade] = [
        Upgrade(name: "Hollow Balls", description: "High damage, lower accuracy.", cost: 800, type: .cannonballType, value: 0, payload: PlayerStats.CannonballType.hollow, condition: { $0.currentCannonball == .standard }),
        Upgrade(name: "Efficient Crew", description: "-0.25s Reload Time", cost: 400, type: .reloadSpeed, value: 0.25, condition: { $0.baseReloadSpeed > 2.75 }),
        Upgrade(name: "Expert Loaders", description: "-0.5s Reload Time", cost: 1000, type: .reloadSpeed, value: 0.5, condition: { $0.baseReloadSpeed <= 2.75 && $0.baseReloadSpeed > 2.0 })
    ]
    let carpenterUpgrades: [Upgrade] = [
        Upgrade(name: "Add Gun Deck", description: "+1 Cannon", cost: 1500, type: .cannonCount, value: 1, condition: { $0.cannonCount == 1 }),
        Upgrade(name: "Add Second Deck", description: "+1 Cannon", cost: 3000, type: .cannonCount, value: 1, condition: { $0.cannonCount == 2 })
    ]

    var body: some View {
        let repairCost = 350
        let canRepair = playerStats.currentHP < playerStats.maxHP || playerStats.currentShield < playerStats.maxShield
        
        ZStack {
            Color.black.opacity(0.7).edgesIgnoringSafeArea(.all)
            VStack(spacing: 15) {
                Text("The Shipyard").font(.system(size: 48, weight: .bold, design: .serif)).foregroundColor(.white)
                Text("Gold: \(playerStats.gold)").font(.title).foregroundColor(.yellow)
                ScrollView {
                    VStack(spacing: 20) {
                        Button(action: {
                            if playerStats.gold >= repairCost {
                                playerStats.gold -= repairCost
                                onRepair()
                            }
                        }) {
                            Text("Full Repairs\n$\(repairCost) Gold").font(.headline).foregroundColor(.white).padding().frame(maxWidth: .infinity)
                                .background(playerStats.gold >= repairCost && canRepair ? Color.orange : Color.gray).cornerRadius(10)
                        }.disabled(playerStats.gold < repairCost || !canRepair).padding(.horizontal)
                        
                        UpgradeSectionView(title: "Gunnery", upgrades: gunneryUpgrades, playerStats: playerStats)
                        UpgradeSectionView(title: "Ordnance", upgrades: ordnanceUpgrades, playerStats: playerStats)
                        UpgradeSectionView(title: "Carpenter", upgrades: carpenterUpgrades, playerStats: playerStats)
                        UpgradeSectionView(title: "Shipyard", upgrades: shipyardUpgrades, playerStats: playerStats)
                    }
                }
                Button(action: onExitStore) {
                    Text("Return to Sea").font(.title2).fontWeight(.semibold).padding().background(Color.blue).foregroundColor(.white).cornerRadius(15)
                }.padding()
            }.padding(.top)
        }
    }
}

struct UpgradeSectionView: View {
    let title: String; let upgrades: [Upgrade]; @ObservedObject var playerStats: PlayerStats
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title2).fontWeight(.bold).padding(.leading)
            ForEach(upgrades.filter { $0.condition == nil || $0.condition!(playerStats) }, id: \.id) { upgrade in
                HStack {
                    VStack(alignment: .leading) {
                        Text(upgrade.name).font(.headline); Text(upgrade.description).font(.caption).opacity(0.8)
                    }
                    Spacer()
                    Button(action: { playerStats.apply(upgrade: upgrade) }) {
                        Text("$\(upgrade.cost)").font(.caption).foregroundColor(.white).padding(8).background(playerStats.gold >= upgrade.cost ? Color.green : Color.gray).cornerRadius(8)
                    }.disabled(playerStats.gold < upgrade.cost)
                }.padding().background(Color.black.opacity(0.2)).cornerRadius(10)
            }
        }.padding(.horizontal)
    }
}

struct MainMenuView: View {
    var onStartGame: () -> Void
    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [.blue, .cyan.opacity(0.7)]), startPoint: .top, endPoint: .bottom).edgesIgnoringSafeArea(.all)
            VStack(spacing: 40) {
                Text("Naval Adventure").font(.system(size: 48, weight: .bold, design: .serif)).foregroundColor(.white).shadow(color: .black.opacity(0.5), radius: 5, x: 0, y: 5)
                Button(action: onStartGame) { Text("Start Game").font(.title2).fontWeight(.semibold).padding(.horizontal, 40).padding(.vertical, 15).background(Color.green).foregroundColor(.white).cornerRadius(15).shadow(radius: 5) }
            }
        }
    }
}

struct GameOverView: View {
    var onRestart: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.8).edgesIgnoringSafeArea(.all)
            VStack(spacing: 30) {
                Text("Game Over").font(.largeTitle).fontWeight(.bold).foregroundColor(.red)
                Button(action: onRestart) { Text("Play Again").font(.title).padding().background(Color.green).foregroundColor(.white).cornerRadius(10) }
            }
        }
    }
}

struct PauseMenuView: View {
    var onResume: () -> Void
    var onMainMenu: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7).edgesIgnoringSafeArea(.all)
            VStack(spacing: 20) {
                Text("Paused").font(.largeTitle).bold().foregroundColor(.white)
                Button("Resume", action: onResume)
                    .font(.title2).padding().background(Color.blue).foregroundColor(.white).cornerRadius(10)
                Button("Main Menu", action: onMainMenu)
                    .font(.title2).padding().background(Color.gray).foregroundColor(.white).cornerRadius(10)
            }
        }
    }
}

struct HUDView: View {
    @ObservedObject var playerStats: PlayerStats
    @ObservedObject var scene: GameScene
    var onPause: () -> Void

    var body: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if playerStats.currentShield > 0 { HStack { Image(systemName: "shield.fill").foregroundColor(.cyan); ProgressView(value: Float(playerStats.currentShield), total: Float(playerStats.maxShield)).tint(.cyan); Text("\(playerStats.currentShield)") } }
                    HStack { Image(systemName: "heart.fill").foregroundColor(.red); ProgressView(value: Float(playerStats.currentHP), total: Float(playerStats.maxHP)).tint(.red); Text("\(playerStats.currentHP)") }
                }.padding().background(Color.black.opacity(0.4)).cornerRadius(10)
                Spacer()
                VStack {
                    Text(scene.currentLevelName).font(.title2).bold().lineLimit(1).minimumScaleFactor(0.5)
                    Text("Gold: \(playerStats.gold)").font(.subheadline).bold()
                }
                Spacer()
                Button(action: onPause) { Image(systemName: "pause.circle.fill").font(.largeTitle) }
            }.padding().foregroundColor(.white)
            
            Spacer()
            
            HStack {
                Spacer()
                Button(action: { scene.toggleAutoFire() }) {
                    HStack {
                        Text(" ")
                        Image(systemName: "flame.fill")
                        Text(scene.isAutoFireOn ? " " : " ")
                    }
                    .font(.headline).foregroundColor(.white).padding()
                    .background((scene.isAutoFireOn ? Color.black.opacity(0.7) : Color.red.opacity(0.85)))
                    .cornerRadius(15).shadow(radius: 5)
                }.padding(.trailing, 20)
            }.padding(.bottom, UIScreen.main.bounds.height * 0.12)
        }
    }
}

struct GameView: View {
    @ObservedObject var playerStats: PlayerStats
    @ObservedObject var scene: GameScene
    var onPause: () -> Void

    var body: some View {
        ZStack {
            SpriteView(scene: scene)
                .edgesIgnoringSafeArea(.all)
            HUDView(playerStats: playerStats, scene: scene, onPause: onPause)
        }
    }
}


// MARK: - Main App Structure
struct ContentView1: View {
    @StateObject private var playerStats = PlayerStats()
    @State private var currentScreen: GameScreen = .mainMenu
    @State private var isGamePaused = true

    @State private var gameScene: GameScene

    init() {
        let scene = GameScene(size: UIScreen.main.bounds.size, stats: nil, gameOverAction: {}, waveClearedAction: {}, isPaused: .constant(true))
        _gameScene = State(initialValue: scene)
    }

    var body: some View {
        ZStack {
            GameView(playerStats: playerStats, scene: gameScene, onPause: {
                isGamePaused = true
                currentScreen = .pause
            })
            .onAppear {
                configureGameScene()
            }

            // --- Overlays ---
            if currentScreen == .mainMenu {
                MainMenuView(onStartGame: {
                    resetGame()
                    gameScene.startGame()
                    currentScreen = .game
                })
            } else if currentScreen == .store {
                StoreView(playerStats: playerStats, onExitStore: {
                    gameScene.resumeGame()
                    currentScreen = .game
                }, onRepair: {
                    healPlayer(amount: playerStats.maxHP + playerStats.maxShield)
                })
            } else if currentScreen == .gameOver {
                GameOverView(onRestart: {
                    resetGame()
                    currentScreen = .mainMenu
                    isGamePaused = true
                })
            } else if currentScreen == .pause {
                PauseMenuView(onResume: {
                    gameScene.isPaused = false
                    isGamePaused = false
                    currentScreen = .game
                }, onMainMenu: {
                    resetGame()
                    currentScreen = .mainMenu
                    isGamePaused = true
                })
            }
        }
    }
    
    func configureGameScene() {
        gameScene.size = UIScreen.main.bounds.size
        gameScene.playerStats = playerStats
        gameScene.onGameOver = { isGamePaused = true; currentScreen = .gameOver }
        gameScene.onWaveCleared = { isGamePaused = true; currentScreen = .store }
        gameScene.isPausedBinding = $isGamePaused
    }
    
    func resetGame() {
        let newStats = PlayerStats()
        playerStats.gold = newStats.gold; playerStats.currentHP = newStats.maxHP; playerStats.currentShield = newStats.currentShield
        playerStats.minDamageMultiplier = newStats.minDamageMultiplier; playerStats.baseShipSpeed = newStats.baseShipSpeed
        playerStats.baseReloadSpeed = newStats.baseReloadSpeed; playerStats.cannonCount = newStats.cannonCount
        playerStats.critChance = newStats.critChance
        playerStats.critDamageMultiplier = newStats.critDamageMultiplier
        // The scene will reset itself when startGame is called
    }
    
    func healPlayer(amount: Int) {
        var remainingHeal = amount
        let neededHP = playerStats.maxHP - playerStats.currentHP
        if neededHP > 0 { let healToHP = min(remainingHeal, neededHP); playerStats.currentHP += healToHP; remainingHeal -= healToHP }
        if remainingHeal > 0 { let neededShield = playerStats.maxShield - playerStats.currentShield; if neededShield > 0 { let healToShield = min(remainingHeal, neededShield); playerStats.currentShield += healToShield; remainingHeal -= healToShield } }
        if remainingHeal > 0 { let interestGold = remainingHeal / 20; playerStats.gold += interestGold }
    }
}

// MARK: - Entry Point
@main
struct NavalAdventureApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView1()
        }
    }
}
