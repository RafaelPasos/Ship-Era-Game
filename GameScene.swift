import SpriteKit
import SwiftUI
import GameplayKit

// MARK: - Core Enums & Structs
enum LootType { case gold, health, repairKit,gold_boss }
enum EnemyType { case standard, captain, boss, chaser }

// MARK: - Game Scene
class GameScene: SKScene, SKPhysicsContactDelegate, ObservableObject {

    // MARK: - Properties
    
    var playerStats: PlayerStats?
    var onGameOver: () -> Void = {}
    var onWaveCleared: () -> Void = {}
    var isPausedBinding: Binding<Bool>

    @Published var targetedEnemy: SKSpriteNode?
    @Published var isAutoFireOn = false
    @Published var currentLevelName: String = "The High Seas"
    
    // NEW: Published properties for skill cooldowns for the UI to observe
    @Published var speedBoostCooldown: Double = 0
    @Published var rapidFireCooldown: Double = 0
    @Published var repairDronesCooldown: Double = 0
    
    private var player: SKSpriteNode!
    private var enemyNodes: [SKSpriteNode] = []
    private var autoFireTimer: Timer?
    private var targetIndicator: SKShapeNode!
    private var playerIndicator: SKShapeNode! // New player indicator
    
    private var lastUpdateTime: TimeInterval = 0
    private var currentWave = 1
    private var levelNames: [String] = []
    private var isWaveInProgress = false
    private var playerMoveTarget: CGPoint?
    private var playableRect: CGRect = .zero
    
    // NEW: Properties to track active skill effects
    private var speedBoostActive = false
    private var rapidFireActive = false
    private var speedBoostTimer: Timer?
    private var rapidFireTimer: Timer?
    private var gameAtlas: SKTextureAtlas!
    
    // Joystick properties
    private var joystickBase: SKShapeNode!
    private var joystickKnob: SKShapeNode!
    private var isJoystickActive = false
    private var joystickVector: CGVector = .zero
    private var joystickTouch: UITouch?


    struct PhysicsCategory {
        static let none         : UInt32 = 0
        static let player       : UInt32 = 0b1
        static let enemy        : UInt32 = 0b10
        static let playerBall   : UInt32 = 0b100
        static let enemyBall    : UInt32 = 0b1000
        static let obstacle     : UInt32 = 0b10000
        static let loot         : UInt32 = 0b100000
    }

    // MARK: - Initializer
    
    init(size: CGSize, stats: PlayerStats?, gameOverAction: @escaping () -> Void, waveClearedAction: @escaping () -> Void, isPaused: Binding<Bool>) {
        self.playerStats = stats
        self.onGameOver = gameOverAction
        self.onWaveCleared = waveClearedAction
        self.isPausedBinding = isPaused
        super.init(size: size)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Scene Lifecycle
    
    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1.0)
        gameAtlas = SKTextureAtlas(named: "GameAtlas")
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
        self.isPaused = true
        
        
        
                let leftMargin = size.width * 0.08
        let rightMargin = size.width * 0.05
        let topMargin = size.height * 0.20
        let bottomMargin = size.height * 0.05
        
        let playableWidth = size.width - leftMargin - rightMargin
        let playableHeight = size.height - topMargin - bottomMargin
        
        playableRect = CGRect(x: leftMargin, y: bottomMargin, width: playableWidth, height: playableHeight)
        
        targetIndicator = SKShapeNode(circleOfRadius: 20)
        targetIndicator.strokeColor = .red
        targetIndicator.lineWidth = 3
        targetIndicator.isHidden = true
        targetIndicator.alpha = 0.4
        targetIndicator.yScale = 0.7
        targetIndicator.zRotation = .pi / 4
        targetIndicator.position.x += targetIndicator.frame.width * 0.7 + 75
        
        
        addChild(targetIndicator)
        
        playerIndicator = SKShapeNode(circleOfRadius: 350)
        playerIndicator.strokeColor = .blue
        playerIndicator.lineWidth = 2
        playerIndicator.alpha = 0.8
        playerIndicator.fillColor = .blue.withAlphaComponent(0.2)
        playerIndicator.position = CGPoint(x: 0, y: -150)
        playerIndicator.zPosition = -1 // Render below the player ship
        
        levelNames = generateLevelNames(count: 100)
    }
    
    override func update(_ currentTime: TimeInterval) {
        self.isPaused = isPausedBinding.wrappedValue
        if self.isPaused { lastUpdateTime = 0; return }
        
        if lastUpdateTime == 0 { lastUpdateTime = currentTime }
        let deltaTime = currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        
        guard let player = player else { return } // Ensure player exists
        
        updatePlayer(deltaTime: deltaTime)
        updateEnemies(deltaTime: deltaTime, playerPosition: player.position)
        updateTargetIndicator()
        updateCooldowns(deltaTime: deltaTime)
        
        clampNodeToPlayableArea(player)
        for enemy in enemyNodes {
            clampNodeToPlayableArea(enemy)
        }
        
        if isWaveInProgress && enemyNodes.isEmpty && children.first(where: {$0.name == "loot"}) == nil {
            if playerStats?.currentHP ?? 0 > 0 {
                isWaveInProgress = false
                isPausedBinding.wrappedValue = true
                onWaveCleared()
            }
        }
    }
    
    // MARK: - Public Game Control Methods
    
    func startGame() {
        self.isPaused = false
        isPausedBinding.wrappedValue = false
        currentWave = 0
        startNextWave()
    }
    
    func resumeGame() {
        self.isPaused = false
        isPausedBinding.wrappedValue = false
        startNextWave()
    }
    
    func toggleAutoFire() {
        if targetedEnemy == nil {
            targetedEnemy = enemyNodes.min(by: { player.position.distance(to: $0.position) < player.position.distance(to: $1.position) })
        }
        
        isAutoFireOn.toggle()
        autoFireTimer?.invalidate()
        
        if isAutoFireOn, let target = targetedEnemy {
            let angle = atan2(target.position.y - player.position.y, target.position.x - player.position.x)
            let rotateAction = SKAction.rotate(toAngle: angle - .pi / 2, duration: 0.2, shortestUnitArc: true)
            player.run(rotateAction) { [weak self] in
                self?.fireCannonball()
                let reloadSpeed = self?.rapidFireActive ?? false ? (self?.playerStats?.baseReloadSpeed ?? 3.0) / 2 : self?.playerStats?.baseReloadSpeed ?? 3.0
                self?.autoFireTimer = Timer.scheduledTimer(withTimeInterval: reloadSpeed, repeats: true) { [weak self] _ in
                    self?.fireCannonball()
                }
            }
        }
    }
    
    // MARK: - Game Setup
    
    func startNextWave() {
        self.removeAllChildren()
        enemyNodes.removeAll()
        targetedEnemy = nil
        isAutoFireOn = false
        autoFireTimer?.invalidate()
        
        isWaveInProgress = true
        
        addChild(targetIndicator)
        
        currentWave += 1
        let levelName = levelNames.indices.contains(currentWave - 1) ? levelNames[currentWave - 1] : "The Endless Sea"
        currentLevelName = "Wave \(currentWave): \(levelName)"
        
        var occupiedFrames: [CGRect] = []
        let hudSafeArea = CGRect(x: 0, y: size.height - 120, width: size.width, height: 120)
        occupiedFrames.append(hudSafeArea)
        
        spawnObstacles(count: 1 + (currentWave/5), occupiedFrames: &occupiedFrames)
        createPlayer(occupiedFrames: &occupiedFrames)
        spawnEnemies(count: 1 + currentWave, occupiedFrames: &occupiedFrames)
        spawnLoot(count: Int(Double(1 + currentWave/3) * 0.7), occupiedFrames: &occupiedFrames)
        setupJoystick()
        if (currentWave != 1){resetJoystick()}
        
        // Add Perlin Noise Overlay
        backgroundColor = SKColor(red: 0.2, green: 0.5, blue: Double.random(in: 0.5...0.8), alpha: 1.0)
        let perlinNoiseTexture = gameAtlas.textureNamed("perlin_noise")
        let perlinNoiseSprite = SKSpriteNode(texture: perlinNoiseTexture)
        perlinNoiseSprite.size = size
        perlinNoiseSprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        perlinNoiseSprite.blendMode = .subtract
        perlinNoiseSprite.alpha = 0.63
        if (currentWave%3 == 0){perlinNoiseSprite.zRotation = .pi}
        perlinNoiseSprite.zPosition = -2 // Behind everything but above background
        addChild(perlinNoiseSprite)
        let perlinNoiseTexture2 = gameAtlas.textureNamed("perlin_noise_2")
        let perlinNoiseSprite2 = SKSpriteNode(texture: perlinNoiseTexture2)
        perlinNoiseSprite2.size = size
        perlinNoiseSprite2.alpha = 0.8
        perlinNoiseSprite2.position = CGPoint(x: size.width / 2, y: size.height / 2)
        if (currentWave%2 == 0){perlinNoiseSprite2.zRotation = .pi}
        perlinNoiseSprite2.blendMode = .multiplyAlpha
        perlinNoiseSprite2.zPosition = -2 // Behind everything but above background
        addChild(perlinNoiseSprite2)
    }

    func createShipNode(isPlayer: Bool, type: EnemyType = .standard, direction: String = "forward") -> SKSpriteNode {
        let textureName: String
        var scale: CGFloat = 0.040 // Base scale for all ships

        if isPlayer {
            if direction != "left" {
                textureName = "player_ship_startercL"
            } else {
                textureName = "player_ship_starterc"
            }
        } else {
            switch type {
            case .boss:
                if direction != "left" {
                    textureName = "boss_shipcL"
                } else {
                    textureName = "boss_shipc"
                }
                scale *= 1.6
            case .captain:
                textureName = "captain_shipc"
                scale *= 0.05
            case .chaser:
                if direction != "left" {
                    textureName = "chaser_shipcL"
                } else {
                    textureName = "chaser_shipc"
                }
                scale=0.055
            default:
                if direction == "left" {
                    textureName = "standard_shipcL"
                } else {
                    textureName = "standard_shipc"
                }
                scale=0.052
            }
        }

        let shipTexture = gameAtlas.textureNamed(textureName)
        let shipNode = SKSpriteNode(texture: shipTexture)
        shipNode.setScale(scale)
        shipNode.userData = NSMutableDictionary()
        shipNode.userData?["type"] = type

        return shipNode
    }
    
    func createPlayer(occupiedFrames: inout [CGRect]) {
        player = createShipNode(isPlayer: true)
        player.position = findSafePosition(size: player.frame.size, occupiedFrames: &occupiedFrames, respectHud: true)
        player.name = "player"
        player.physicsBody = SKPhysicsBody(rectangleOf: player.frame.size)
        player.physicsBody?.categoryBitMask = PhysicsCategory.player
        player.physicsBody?.contactTestBitMask = PhysicsCategory.enemyBall | PhysicsCategory.loot
        player.physicsBody?.collisionBitMask = PhysicsCategory.obstacle | PhysicsCategory.enemy
        player.physicsBody?.allowsRotation = false
        addChild(player)
        player.addChild(playerIndicator) // Add indicator as child of player
    }
    
    //func createPalmTree() -> SKNode {
    //    let palmTexture = gameAtlas.textureNamed("palm_tree")
    //    let tree = SKSpriteNode(texture: palmTexture)
    //    tree.setScale(0.2)
    //    return tree
    //
    //}
    func setupJoystick() {
        let baseSize = CGSize(width: 120, height: 120)
        let knobSize = CGSize(width: 60, height: 60)

        joystickBase = SKShapeNode(circleOfRadius: baseSize.width / 2)
        joystickBase.fillColor = SKColor.gray.withAlphaComponent(0.5)
        joystickBase.strokeColor = .clear
        joystickBase.position = CGPoint(x: 100, y: 100)
        joystickBase.zPosition = 10
        addChild(joystickBase)

        joystickKnob = SKShapeNode(circleOfRadius: knobSize.width / 2)
        joystickKnob.fillColor = SKColor.darkGray.withAlphaComponent(0.8)
        joystickKnob.strokeColor = .clear
        joystickKnob.position = joystickBase.position
        joystickKnob.zPosition = 11
        addChild(joystickKnob)
    }

    func spawnObstacles(count: Int, occupiedFrames: inout [CGRect]) {
        let islandTextures = ["island_1", "island_2", "island_3", "island_4"]
        for _ in 0..<count {
            let randomIslandTextureName = islandTextures.randomElement()!
            let islandTexture = gameAtlas.textureNamed(randomIslandTextureName)
            let obstacleNode = SKSpriteNode(texture: islandTexture)
            let scale = CGFloat.random(in: 0.11...0.13)
            obstacleNode.setScale(scale)
            obstacleNode.position = findSafePosition(size: obstacleNode.size, occupiedFrames: &occupiedFrames)
            
            //if Double.random(in: 0...1) < 0.4 {
             //   let palm = createPalmTree()
             //   palm.position = CGPoint(x: CGFloat.random(in: -20...20), y: CGFloat.random(in: -20...20))
             //   obstacleNode.addChild(palm)
            //}
            
            obstacleNode.name = "obstacle"
            obstacleNode.physicsBody = SKPhysicsBody(texture: islandTexture, size: obstacleNode.size)
            obstacleNode.physicsBody?.isDynamic = false
            obstacleNode.physicsBody?.categoryBitMask = PhysicsCategory.obstacle
            addChild(obstacleNode)
        }
    }
    
    func spawnLoot(count: Int, occupiedFrames: inout [CGRect]) {
        for _ in 0..<count {
            let lootType: LootType = Double.random(in: 0...1) < 0.7 ? .gold : .health
            let lootNode: SKSpriteNode
            let textureName: String
            
            switch lootType {
                case .gold: textureName = "gold_coinc"
                case .gold_boss: textureName = "gold_coincb"
                case .health: textureName = "repair_kitd"
                case .repairKit: textureName = "repair_kitd"
            }
            
            let lootTexture = gameAtlas.textureNamed(textureName)
            lootNode = SKSpriteNode(texture: lootTexture)
            lootNode.setScale(0.04) // Adjust scale as needed
            lootNode.name = "loot"
            lootNode.zPosition = -1
            lootNode.position = findSafePosition(size: lootNode.frame.size, occupiedFrames: &occupiedFrames, respectHud: true)
            lootNode.userData = ["type": lootType, "value": lootType == .gold ? 50 : 50]
            
            lootNode.physicsBody = SKPhysicsBody(texture: lootTexture, size: lootNode.size)
            lootNode.physicsBody?.categoryBitMask = PhysicsCategory.loot
            lootNode.physicsBody?.contactTestBitMask = PhysicsCategory.player // Only player should contact loot
            lootNode.physicsBody?.collisionBitMask = PhysicsCategory.none
            addChild(lootNode)

        }
    }

    func spawnEnemies(count: Int, occupiedFrames: inout [CGRect]) {
        var remainingEnemies = count
        if currentWave % 3 == 0 { spawnEnemy(type: .boss, occupiedFrames: &occupiedFrames); remainingEnemies -= 1 }
        if Double.random(in: 0...1) < 0.1 { spawnEnemy(type: .boss, occupiedFrames: &occupiedFrames); remainingEnemies -= 1 }
        for _ in 0..<max(0, remainingEnemies) {
            let type: EnemyType = Double.random(in: 0...1) < 0.3 ? .chaser : .standard
            spawnEnemy(type: type, occupiedFrames: &occupiedFrames)
        }
    }
    
    func spawnEnemy(type: EnemyType, occupiedFrames: inout [CGRect]) {
        let enemyNode = createShipNode(isPlayer: false, type: type)
        enemyNode.position = findSafePosition(size: enemyNode.size, occupiedFrames: &occupiedFrames, inTopHalf: true)
        enemyNode.name = "enemy"
        
        enemyNode.physicsBody = SKPhysicsBody(rectangleOf: enemyNode.frame.size)
        enemyNode.physicsBody?.categoryBitMask = PhysicsCategory.enemy
        enemyNode.physicsBody?.contactTestBitMask = PhysicsCategory.playerBall
        enemyNode.physicsBody?.collisionBitMask = PhysicsCategory.obstacle | PhysicsCategory.player
        
        let maxHp = (type == .boss) ? 300 + (currentWave * 25) : 100 + (currentWave * 20)
        enemyNode.userData?["hp"] = maxHp
        enemyNode.userData?["maxHp"] = maxHp // Store max HP
        enemyNode.userData?["fireCooldown"] = 3.0
        
        if type == .chaser || type == .boss {
            enemyNode.userData?["chaseCooldown"] = Double.random(in: 3...5)
            enemyNode.userData?["isChasing"] = true
        }
        
        let (healthBarBackground, healthBar) = createHealthBar(for: enemyNode)
        enemyNode.addChild(healthBarBackground)
        enemyNode.userData?["healthBar"] = healthBar // Store reference to the inner health bar

        // Add enemy name label
        let enemyName = generateEnemyName()
        let nameLabel = SKLabelNode(text: enemyName)
        nameLabel.fontName = "Helvetica"
        nameLabel.fontSize = 172
        nameLabel.fontColor = .white
        nameLabel.position = CGPoint(x: 0, y: -650) // Position below the ship
        nameLabel.zPosition = 15 // Ensure it's above the ship
        enemyNode.addChild(nameLabel)
        enemyNode.userData?["nameLabel"] = nameLabel

        enemyNodes.append(enemyNode)
        addChild(enemyNode)
    }
    
    func createHealthBar(for enemy: SKSpriteNode) -> (SKShapeNode, SKShapeNode) {
        let barWidth: CGFloat = 700 // Fixed width for health bar
        let barHeight: CGFloat = 40
        let healthBarBackground = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 2)
        healthBarBackground.fillColor = .darkGray
        healthBarBackground.strokeColor = .clear
        healthBarBackground.position = CGPoint(x: 0, y: -450) // Position below the ship
        healthBarBackground.zPosition = 1 // Ensure it's above the ship

        let healthBar = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 2)
        healthBar.fillColor = .green // Start green
        healthBar.strokeColor = .clear
        healthBar.position = CGPoint(x: 0, y: 0)
        healthBar.zPosition = 2 // Ensure it's above the background

        healthBarBackground.addChild(healthBar)
        return (healthBarBackground, healthBar)
    }

    func findSafePosition(size objectSize: CGSize, occupiedFrames: inout [CGRect], inTopHalf: Bool = false, respectHud: Bool = false) -> CGPoint {
        var position: CGPoint; var attempts = 0
        let margin: CGFloat = 20
        
        var proposedFrame: CGRect
        repeat {
            let xRange = playableRect.minX + margin...playableRect.maxX - margin
            let yRange = inTopHalf ? (size.height / 2)...(playableRect.maxY - margin) : playableRect.minY + margin...(size.height - margin)
            
            position = CGPoint(x: CGFloat.random(in: xRange), y: CGFloat.random(in: yRange))
            proposedFrame = CGRect(x: position.x - objectSize.width / 2, y: position.y - objectSize.height / 2, width: objectSize.width, height: objectSize.height).insetBy(dx: -margin, dy: -margin)
            attempts += 1
        } while (occupiedFrames.contains { $0.intersects(proposedFrame) }) && attempts < 100
        
        occupiedFrames.append(proposedFrame)
        return position
    }

    // MARK: - Input, AI, and Movement
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !self.isPaused else { return }
        for touch in touches {
            let location = touch.location(in: self)
            if joystickBase.frame.contains(location) && joystickTouch == nil {
                joystickTouch = touch
                isJoystickActive = true
            } else if let tappedNode = nodes(at: location).first(where: { $0.name == "enemy" }) as? SKSpriteNode {
                targetedEnemy = tappedNode
                isAutoFireOn = false
                autoFireTimer?.invalidate()
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !self.isPaused, let touch = joystickTouch else { return }
        let location = touch.location(in: self)
        let vector = CGVector(dx: location.x - joystickBase.position.x, dy: location.y - joystickBase.position.y)
        let angle = atan2(vector.dy, vector.dx)
        let length = joystickBase.frame.width / 2
        let x = length * cos(angle)
        let y = length * sin(angle)

        if joystickBase.frame.contains(location) {
            joystickKnob.position = location
        } else {
            joystickKnob.position = CGPoint(x: joystickBase.position.x + x, y: joystickBase.position.y + y)
        }
        joystickVector = vector
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if touch == joystickTouch {
                resetJoystick()
                joystickTouch = nil
            }
        }
    }

    func resetJoystick() {
        isJoystickActive = false
        joystickVector = .zero
        let returnAction = SKAction.move(to: joystickBase.position, duration: 0.1)
        returnAction.timingMode = .easeOut
        joystickKnob.run(returnAction)
        //joystickKnob.position = CGPoint.zero
        
    }
    
    func updatePlayer(deltaTime: TimeInterval) {
        if isJoystickActive {
            let speed = speedBoostActive ? (playerStats?.baseShipSpeed ?? 1) * 1.1 : (playerStats?.baseShipSpeed ?? 1)
            let angle = atan2(joystickVector.dy, joystickVector.dx)
            let dx = cos(angle) * speed * 100
            let dy = sin(angle) * speed * 100
            player.physicsBody?.velocity = CGVector(dx: dx, dy: dy)
            player.zRotation = angle - .pi / 2

            // Update player ship texture based on direction
            let newTextureName: String
            if dx < 0 {
                newTextureName = "player_ship_startercL"
            } else {
                newTextureName = "player_ship_starterc"
            }
            if player.texture?.description != gameAtlas.textureNamed(newTextureName).description {
                player.texture = gameAtlas.textureNamed(newTextureName)
            }

        } else {
            player.physicsBody?.velocity = .zero
            player.zRotation = 0

            // Reset player ship texture when stationary
            let newTextureName = "player_ship_starterc"
            if player.texture?.description != gameAtlas.textureNamed(newTextureName).description {
                player.texture = gameAtlas.textureNamed(newTextureName)
            }
        }

        if let target = targetedEnemy {
            let firingAngle = atan2(target.position.y - player.position.y, target.position.x - player.position.x)
            player.userData?["firingAngle"] = firingAngle
            
            if !isJoystickActive {
                //player.zRotation = firingAngle - .pi / 2
                player.zRotation = 0
            }
        }
    }
    
    func updateEnemies(deltaTime: TimeInterval, playerPosition: CGPoint) {
        guard let playerStats = playerStats else { return } // Ensure playerStats is not nil
        for enemy in enemyNodes {
            let type = enemy.userData?["type"] as? EnemyType ?? .standard
            
            let keepDistance: CGFloat = self.size.height * 0.15 // 15% of screen height
            let distanceToPlayer = enemy.position.distance(to: playerPosition)
            let angle = atan2(playerPosition.y - enemy.position.y, playerPosition.x - enemy.position.x)
            
                        
            if type == .chaser || type == .boss {
                var speed: CGFloat
                if distanceToPlayer > keepDistance + 20 { // Move towards if too far
                    speed = (playerStats.baseShipSpeed ?? 1) * (type == .boss ? 0.5 : 0.4)
                    enemy.physicsBody?.velocity = CGVector(dx: cos(angle) * speed * 100, dy: sin(angle) * speed * 100)
                } else if distanceToPlayer < keepDistance - 20 { // Move away if too close
                    speed = (playerStats.baseShipSpeed ?? 1) * (type == .boss ? 0.3 : 0.2)
                    enemy.physicsBody?.velocity = CGVector(dx: -cos(angle) * speed * 100, dy: -sin(angle) * speed * 100)
                } else { // Maintain distance
                    enemy.physicsBody?.velocity = .zero
                }
                //enemy.zRotation = angle - .pi / 2
                enemy.zRotation = 0
            } else { // Standard enemies
                let firingRange = self.size.height * 0.32
                if distanceToPlayer <= firingRange {
                    // In range, stop moving and fire
                    enemy.physicsBody?.velocity = .zero
                    enemy.zRotation = 0 // Keep orientation
                } else {
                    // Out of range, move randomly
                    var randomMoveCooldown = enemy.userData?["randomMoveCooldown"] as? Double ?? 3.0
                    var randomMoveTarget = enemy.userData?["randomMoveTarget"] as? CGPoint

                    if randomMoveTarget == nil || enemy.position.distance(to: randomMoveTarget!) < 50 || randomMoveCooldown <= 0 {
                        // Pick a new random target
                        randomMoveTarget = generateRandomPointInPlayableArea()
                        enemy.userData?["randomMoveTarget"] = randomMoveTarget
                        randomMoveCooldown = Double.random(in: 7.0...10.0) // Reset cooldown
                        enemy.userData?["randomMoveCooldown"] = randomMoveCooldown
                    }

                    if let target = randomMoveTarget {
                        let moveAngle = atan2(target.y - enemy.position.y, target.x - enemy.position.x)
                        let speed = (playerStats.baseShipSpeed ?? 1) * 0.3 // Slower than chasers
                        enemy.physicsBody?.velocity = CGVector(dx: cos(moveAngle) * speed * 100, dy: sin(moveAngle) * speed * 100)
                        enemy.zRotation = 0 // Orient towards movement
                    }
                    enemy.userData?["randomMoveCooldown"] = randomMoveCooldown - deltaTime
                }
            }
            
            // Update enemy ship texture based on direction
            let enemyTextureName: String
            if enemy.physicsBody?.velocity.dx ?? 0 < 0 {
                switch type {
                case .boss:
                    enemyTextureName = "boss_shipc"
                case .chaser:
                    enemyTextureName = "chaser_shipc"
                default:
                    enemyTextureName = "standard_shipc"
                }
            } else {
                switch type {
                case .boss:
                    enemyTextureName = "boss_shipcL"
                case .chaser:
                    enemyTextureName = "chaser_shipcL"
                default:
                    enemyTextureName = "standard_shipcL"
                }
            }
            if enemy.texture?.description != gameAtlas.textureNamed(enemyTextureName).description {
                enemy.texture = gameAtlas.textureNamed(enemyTextureName)
            }

            if var cooldown = enemy.userData?["fireCooldown"] as? Double {
                cooldown -= deltaTime
                enemy.userData?["fireCooldown"] = cooldown
                if cooldown <= 0 {
                    let distanceToPlayer = enemy.position.distance(to: playerPosition)
                    if distanceToPlayer < self.size.height * 0.32 {
                        fireEnemyCannonball(from: enemy)
                    }
                    let baseReload: Double = Double.random(in: 3.0...5.0); let waveBonus = Double(currentWave) * 0.1
                    enemy.userData?["fireCooldown"] = max(2.0, baseReload - waveBonus)
                }
            }
        }
    }
    
    func generateRandomPointInPlayableArea() -> CGPoint {
        let x = CGFloat.random(in: playableRect.minX...playableRect.maxX)
        let y = CGFloat.random(in: playableRect.minY...playableRect.maxY)
        return CGPoint(x: x, y: y)
    }

    func updateTargetIndicator() {
        if let target = targetedEnemy {
            if target.parent == nil {
                self.targetedEnemy = nil; self.isAutoFireOn = false; self.autoFireTimer?.invalidate()
                targetIndicator.isHidden = true
            } else {
                targetIndicator.position = target.position; targetIndicator.isHidden = false
            }
        } else { targetIndicator.isHidden = true }
    }

    func updateCooldowns(deltaTime: TimeInterval) {
        DispatchQueue.main.async {
            if self.speedBoostCooldown > 0 {
                self.speedBoostCooldown = max(0, self.speedBoostCooldown - deltaTime)
            }
            if self.rapidFireCooldown > 0 {
                self.rapidFireCooldown = max(0, self.rapidFireCooldown - deltaTime)
            }
            if self.repairDronesCooldown > 0 {
                self.repairDronesCooldown = max(0, self.repairDronesCooldown - deltaTime)
            }
        }
    }

    // MARK: - Firing & Damage
    
    func fireCannonball() {
        guard !self.isPaused, let playerNode = self.player, let stats = self.playerStats else {
            isAutoFireOn = false; autoFireTimer?.invalidate(); return
        }
        
        for _ in 0..<stats.cannonCount { // Fire stats.cannonCount logical projectiles
            let ballTexture = gameAtlas.textureNamed("player_ball")
            
            // Define actions once
            let moveActionDuration = 2.0
            let waitActionDuration = 3.0
            let removeAction = SKAction.removeFromParent()

            for i in 0..<3 { // Create 3 visual projectiles for each logical projectile
                let ball = SKSpriteNode(texture: ballTexture)
                ball.setScale(0.030)
                ball.position = playerNode.position
                
                let baseFiringAngle = playerNode.userData?["firingAngle"] as? CGFloat ?? playerNode.zRotation + .pi / 2
                playerNode.zRotation = playerNode.zRotation - .pi / 2
                // Introduce variations
                let angleVariation = CGFloat.random(in: -0.05...0.05) // Small angle spread
                let speedMultiplier = CGFloat.random(in: 0.4...0.6) // Speed variation
                let curveOffset = CGFloat.random(in: -50...50) // Perpendicular offset for curve
                
                let finalAngle = baseFiringAngle + angleVariation
                
                // Calculate initial velocity components
                var dx = cos(finalAngle) * 1500 * speedMultiplier
                var dy = sin(finalAngle) * 1500 * speedMultiplier
                
                // Add a perpendicular component for the curve effect
                let perpendicularDx = -sin(finalAngle) * curveOffset
                let perpendicularDy = cos(finalAngle) * curveOffset
                
                dx += perpendicularDx
                dy += perpendicularDy
                
                let moveAction = SKAction.move(by: CGVector(dx: dx, dy: dy), duration: moveActionDuration)
                let waitAction = SKAction.wait(forDuration: waitActionDuration)
                
                ball.run(SKAction.sequence([moveAction, waitAction, removeAction]))
                addChild(ball)
                
                // All visual projectiles get a physics body for collision and disappearing
                ball.physicsBody = SKPhysicsBody(texture: ballTexture, size: ball.size)
                ball.physicsBody?.categoryBitMask = PhysicsCategory.playerBall
                ball.physicsBody?.contactTestBitMask = PhysicsCategory.enemy | PhysicsCategory.obstacle
                ball.physicsBody?.collisionBitMask = PhysicsCategory.none
                
                if i == 0 { // Only the first visual projectile is the "functional" one
                    ball.name = "playerBall"
                    ball.userData = ["damage": stats.getCannonballDamage()] // Set damage for the functional projectile
                }
            }
        }
    }
    
    func fireEnemyCannonball(from enemy: SKSpriteNode) {
        guard let playerNode = self.player, let type = enemy.userData?["type"] as? EnemyType else { return }
        
        let isBoss = type == .boss
        let ballTextureName = isBoss ? "enemy_ball_boss" : "enemy_ball"
        let ballTexture = gameAtlas.textureNamed(ballTextureName)
        let ball = SKSpriteNode(texture: ballTexture)
        ball.setScale(isBoss ? 0.04 : 0.032)
        ball.position = enemy.position
        
        var damage = 20 + Int(Double(currentWave) * 2.0)
        if isBoss {
            let damageMultiplier = Double.random(in: 1.2...1.5)
            damage = Int(Double(damage) * damageMultiplier)
            if Double.random(in: 0...1) < 0.25 {
                damage = Int(Double(damage) * 1.5)
            }
        }
        ball.userData = ["damage": damage]
        
        ball.physicsBody = SKPhysicsBody(texture: ballTexture, size: ball.size)
        ball.physicsBody?.categoryBitMask = PhysicsCategory.enemyBall
        ball.physicsBody?.contactTestBitMask = PhysicsCategory.player | PhysicsCategory.obstacle
        ball.physicsBody?.collisionBitMask = PhysicsCategory.player | PhysicsCategory.obstacle
        
        let angle = atan2(playerNode.position.y - enemy.position.y, playerNode.position.x - enemy.position.x)
        let dx = cos(angle) * 1000
        let dy = sin(angle) * 1000
        
        let speedMultiplier = isBoss ? 1.1 : 1.0 - min(0.5, Double(currentWave) * 0.05)
        let moveAction = SKAction.move(by: CGVector(dx: dx, dy: dy), duration: 3.2 / speedMultiplier)
        ball.run(SKAction.sequence([moveAction, .removeFromParent()]))
        addChild(ball)
    }

    func showFloatingText(at position: CGPoint, text: String, color: SKColor, isCritical: Bool) {
        let indicator = SKLabelNode(text: text)
        indicator.fontName = "Helvetica-Bold"
        indicator.fontSize = isCritical ? 24 : 18
        indicator.fontColor = color
        indicator.position = position
        addChild(indicator)
        
        let moveUp = SKAction.moveBy(x: 0, y: 50, duration: isCritical ? 4.0 : 2.0)
        let scaleUp = SKAction.scale(to: isCritical ? 1.3 : 1.0, duration: 0.7)
        let moveLeft = SKAction.moveBy(x: isCritical ? 40 : 0, y: 0, duration: 3.5)
        let fadeOut = SKAction.fadeOut(withDuration: isCritical ? 3.5 : 2.0)
        indicator.run(SKAction.group([moveUp, fadeOut, scaleUp, moveLeft]), completion: {
            indicator.removeFromParent()
        })
    }
    
    // MARK: - Physics
    
    func didBegin(_ contact: SKPhysicsContact) { handleCollision(body1: contact.bodyA, body2: contact.bodyB) }
    
    func handleCollision(body1: SKPhysicsBody, body2: SKPhysicsBody) {
        if (body1.categoryBitMask == PhysicsCategory.enemy && body2.categoryBitMask == PhysicsCategory.playerBall) { handleHit(enemyBody: body1, ballBody: body2) }
        else if (body2.categoryBitMask == PhysicsCategory.enemy && body1.categoryBitMask == PhysicsCategory.playerBall) { handleHit(enemyBody: body2, ballBody: body1) }
        
        else if (body1.categoryBitMask == PhysicsCategory.player && body2.categoryBitMask == PhysicsCategory.enemyBall) { handleHit(playerBody: body1, ballBody: body2) }
        else if (body2.categoryBitMask == PhysicsCategory.player && body1.categoryBitMask == PhysicsCategory.enemyBall) { handleHit(playerBody: body2, ballBody: body1) }
        
        else if (body1.categoryBitMask == PhysicsCategory.obstacle && body2.categoryBitMask & (PhysicsCategory.playerBall | PhysicsCategory.enemyBall) != 0) { body2.node?.removeFromParent() }
        else if (body2.categoryBitMask == PhysicsCategory.obstacle && body1.categoryBitMask & (PhysicsCategory.playerBall | PhysicsCategory.enemyBall) != 0) { body1.node?.removeFromParent() }
        
        else if (body1.categoryBitMask == PhysicsCategory.player && body2.categoryBitMask == PhysicsCategory.loot) { handleLoot(lootBody: body2) }
        else if (body2.categoryBitMask == PhysicsCategory.player && body1.categoryBitMask == PhysicsCategory.loot) { handleLoot(lootBody: body1) }
    }
    
    func handleHit(enemyBody: SKPhysicsBody, ballBody: SKPhysicsBody) {
        guard let enemyNode = enemyBody.node as? SKSpriteNode, let ballNode = ballBody.node,
              var currentHP = enemyNode.userData?["hp"] as? Int, let maxHp = enemyNode.userData?["maxHp"] as? Int, let stats = playerStats else { return }
        
        ballNode.removeFromParent()
        
        // Only apply damage if the ball has a "damage" property (i.e., it's the functional projectile)
        if ballNode.userData?["damage"] is Int {
            let fireDistance = player.position.distance(to: enemyNode.position)
            let proximityCritChance = fireDistance < size.height * 0.1 ? 0.85 : stats.critChance
            let isCritical = Double.random(in: 0...1) <= proximityCritChance
            
            let maxAccuracyDist = size.height * 0.2
            let minAccuracyDist = size.height * 0.45
            let maxDamageMultiplier = 1.0
            let minDamageMultiplier = stats.minDamageMultiplier
            var currentDamageMultiplier = 1.0
            
            if fireDistance > maxAccuracyDist {
                let progress = (fireDistance - maxAccuracyDist) / (minAccuracyDist - maxAccuracyDist)
                let clampedProgress = max(0, min(1, progress))
                currentDamageMultiplier = maxDamageMultiplier - ((maxDamageMultiplier - minDamageMultiplier) * clampedProgress)
            }
            
            let randomDamageRoll = Double.random(in: currentDamageMultiplier...1.0)
            let distanceAdjustedDamage = Double(stats.getCannonballDamage()) * randomDamageRoll
            
            var finalDamage = Int(distanceAdjustedDamage)
            if isCritical { finalDamage = Int(Double(finalDamage) * stats.critDamageMultiplier) }
            
            currentHP -= finalDamage
            enemyNode.userData?["hp"] = currentHP

            // Check for smoke effect
            let healthPercentage = CGFloat(currentHP) / CGFloat(maxHp)
            if healthPercentage < 0.25 {
                if enemyNode.userData?["fireEmitter"] == nil {
                    if let firePath = Bundle.main.path(forResource: "FireParticle", ofType: "sks"),
                       let data = FileManager.default.contents(atPath: firePath), // Read file into Data
                       let fireEmitter = try? NSKeyedUnarchiver.unarchivedObject(ofClass: SKEmitterNode.self, from: data) {
                        fireEmitter.position = CGPoint(x: 0, y: -70) // Position at the back of the ship
                        fireEmitter.zPosition = 10 // Ensure it's above the ship
                        fireEmitter.particleScale *= 10.0
                        fireEmitter.alpha = 0.3
                        enemyNode.addChild(fireEmitter)
                        enemyNode.userData?["fireEmitter"] = fireEmitter
                    }
                }
            }
            if healthPercentage < 0.50 {
                if enemyNode.userData?["smokeEmitter"] == nil {
                    if let smokePath = Bundle.main.path(forResource: "SmokeParticle", ofType: "sks"),
                       let data = FileManager.default.contents(atPath: smokePath), // Read file into Data
                       let smokeEmitter = try? NSKeyedUnarchiver.unarchivedObject(ofClass: SKEmitterNode.self, from: data) {
                        smokeEmitter.position = CGPoint(x: 20, y: 5) // Position at the back of the ship
                        smokeEmitter.zPosition = 10 // Ensure it's above the ship
                        smokeEmitter.particleScale *= 8.0
                        smokeEmitter.alpha = 0.3
                        enemyNode.addChild(smokeEmitter)
                        enemyNode.userData?["smokeEmitter"] = smokeEmitter
                    }
                }
            } else {
                if let smokeEmitter = enemyNode.userData?["smokeEmitter"] as? SKEmitterNode {
                    smokeEmitter.removeFromParent()
                    enemyNode.userData?["smokeEmitter"] = nil
                }
                if let fireEmitter = enemyNode.userData?["fireEmitter"] as? SKEmitterNode {
                    fireEmitter.removeFromParent()
                    enemyNode.userData?["fireEmitter"] = nil
                }
            }
            
            showFloatingText(at: enemyNode.position, text: "-\(finalDamage)HP", color: isCritical ? .orange : .red, isCritical: isCritical)

            // Update health bar
            if let healthBar = enemyNode.userData?["healthBar"] as? SKShapeNode,
               let healthBarBackground = healthBar.parent as? SKShapeNode {

                let healthPercentage = CGFloat(currentHP) / CGFloat(maxHp)
                
                // Clamp healthPercentage to avoid negative or excessive scaling
                let clampedHealthPercentage = max(0, min(1, healthPercentage))

                // Adjust xScale to change width
                healthBar.xScale = clampedHealthPercentage
                
                // Adjust position to make it appear to shrink from the left
                // The original width of the healthBar is healthBarBackground.frame.width
                let originalWidth = healthBarBackground.frame.width
                healthBar.position.x = (originalWidth * (clampedHealthPercentage - 1)) / 2

                // Update color from green to red with more vibrant yellow/orange
                healthBar.fillColor = SKColor(red: min(1.0, (1.0 - clampedHealthPercentage) * 1.5), green: clampedHealthPercentage, blue: 0, alpha: 1.0)
            }
        }
        
        if currentHP <= 0 {
            enemyBody.velocity = .zero
            if let smokeEmitter = enemyNode.userData?["smokeEmitter"] as? SKEmitterNode {
                smokeEmitter.removeFromParent()
            }
            if let fireEmitter = enemyNode.userData?["fireEmitter"] as? SKEmitterNode {
                fireEmitter.removeFromParent()
            }
            if let nameLabel = enemyNode.userData?["nameLabel"] as? SKLabelNode {
                nameLabel.removeFromParent()
            }

            // Add explosion particle effect
            if let explosionPath = Bundle.main.path(forResource: "ExplosionParticle", ofType: "sks"),
               let data = FileManager.default.contents(atPath: explosionPath), // Read file into Data
               let explosionEmitter = try? NSKeyedUnarchiver.unarchivedObject(ofClass: SKEmitterNode.self, from: data) {
                explosionEmitter.position = enemyNode.position
                explosionEmitter.zPosition = 100 // Ensure it's on top
                explosionEmitter.particleScale *= 0.4 // Adjust size as needed
                explosionEmitter.numParticlesToEmit = 100 // Adjust number of particles
                explosionEmitter.particleLifetime = 0.05 // Adjust lifetime
                
                addChild(explosionEmitter)

                // Remove the emitter after its duration
                explosionEmitter.run(SKAction.sequence([
                    SKAction.wait(forDuration: 0.5),
                    SKAction.removeFromParent()
                ]))
            }

            if let index = enemyNodes.firstIndex(of: enemyNode) { enemyNodes.remove(at: index) }
            let type = enemyNode.userData?["type"] as? EnemyType ?? .standard
            if type == .boss {
                stats.gold += 500
                showFloatingText(at: player.position, text: "$\(500)", color: .yellow, isCritical: false)
            } else {
                stats.gold += 100
                showFloatingText(at: player.position, text: "$\(100)", color: .yellow, isCritical: false)
            }
            enemyNode.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.5),
                SKAction.removeFromParent()
            ]))
        }
    }

    func handleHit(playerBody: SKPhysicsBody, ballBody: SKPhysicsBody) {
        guard let ballNode = ballBody.node, let stats = playerStats, let damage = ballNode.userData?["damage"] as? Int else { return }
        ballNode.removeFromParent()
        
        var damageToDeal = damage
        
        if stats.currentShield > 0 {
            let damageToShield = min(damageToDeal, stats.currentShield)
            playerStats?.currentShield -= damageToShield
            damageToDeal -= damageToShield
        }
        
        if damageToDeal > 0 {
            playerStats?.currentHP -= damageToDeal
        }
        
        showFloatingText(at: playerBody.node!.position, text: "-\(damage)HP", color: .red, isCritical: false)
        if (playerStats?.currentHP ?? 0) <= 0 { onGameOver() }
    }
    
    func handleLoot(lootBody: SKPhysicsBody) {
        guard let lootNode = lootBody.node, let data = lootNode.userData, let stats = playerStats else { return }
        let type = data["type"] as? LootType ?? .gold
        let value = data["value"] as? Int ?? 0
        let position = lootNode.position

        switch type {
        case .gold:
            stats.gold += value
            showFloatingText(at: position, text: "$\(value)", color: .yellow, isCritical: false)
        case .gold_boss:
            stats.gold += value
            showFloatingText(at: position, text: "$\(value)", color: .yellow, isCritical: true)
        case .health:
            healPlayer(amount: value)
        case .repairKit:
            healPlayer(amount: stats.maxHP + stats.maxShield)
        }
        lootNode.removeFromParent()
    }
    
    func spawnLoot(type: LootType, value: Int, at position: CGPoint) {
        let lootNode: SKSpriteNode
        let textureName: String
        
        switch type {
            case .gold: textureName = "gold_coinc"
            case .gold_boss: textureName = "gold_coincb"
            case .health: textureName = "repair_kitd"
            case .repairKit: textureName = "repair_kitd"
        }
        
        let lootTexture = gameAtlas.textureNamed(textureName)
        lootNode = SKSpriteNode(texture: lootTexture)
        lootNode.setScale(0.04) // Adjust scale as needed
        lootNode.name = "loot"
        lootNode.position = position
        lootNode.userData = ["type": type, "value": value]
        
        lootNode.physicsBody = SKPhysicsBody(texture: lootTexture, size: lootNode.size)
        lootNode.physicsBody?.categoryBitMask = PhysicsCategory.loot
        lootNode.physicsBody?.collisionBitMask = PhysicsCategory.none
        addChild(lootNode)
    }
    
    func healPlayer(amount: Int) {
        guard let stats = playerStats else { return }
        showFloatingText(at: player.position, text: "+\(amount)HP", color: .green, isCritical: false)
        var remainingHeal = amount
        let neededHP = stats.maxHP - stats.currentHP
        if neededHP > 0 { let healToHP = min(remainingHeal, neededHP); playerStats?.currentHP += healToHP; remainingHeal -= healToHP }
        if remainingHeal > 0 { let neededShield = stats.maxShield - stats.currentShield; if neededShield > 0 { let healToShield = min(remainingHeal, neededShield); playerStats?.currentShield += healToShield; remainingHeal -= healToShield } }
        if remainingHeal > 0 { let interestGold = remainingHeal / 20; playerStats?.gold += interestGold }
    }
    
    func generateLevelNames(count: Int) -> [String] {
        let adjectives = ["Old", "New", "Sunken", "Forgotten", "Lost", "Black", "Golden", "Broken"]
        let nouns = ["Port", "Beach", "Cove", "Island", "Point", "Reef", "Harbor", "Bay"]
        let lastNames = ["Smith", "Jones", "Williams", "Brown", "Davis", "Miller", "Wilson", "Moore", "Taylor", "Anderson", "Thomas", "Jackson", "White", "Harris", "Martin", "Thompson", "Garcia", "Martinez", "Rodriguez", "Hernandez", "Lopez", "Gonzalez", "Perez"]
        var names: [String] = []
        for _ in 0..<count { names.append("\(adjectives.randomElement()!) \(lastNames.randomElement()!) \(nouns.randomElement()!)") }
        return names
    }
    
    func generateEnemyName() -> String {
        let prefixes = ["Captain", "Admiral", "Rusty", "Iron", "Black", "Red", "Dirty", "Little"]
        let suffixes = ["beard", "hook", "tooth", "fang", "bane", "reaver", "storm", "tide"]
        let names = ["Jhonson", "Rupert", "Williams", "Cerlako", "Mondan", "Firelli", "Rustono", "Bernosa"]
        
        let randomPrefix = prefixes.randomElement() ?? ""
        let randomSuffix = suffixes.randomElement() ?? ""
        let randomName = names.randomElement() ?? ""
        
        return "\(randomPrefix) \(randomName)" // You can adjust the format as needed
    }
    
    

    func clampNodeToPlayableArea(_ node: SKNode) {
        let position = node.position
        
        if position.x < playableRect.minX {
            node.position.x = playableRect.minX
            node.physicsBody?.velocity.dx = max(0, node.physicsBody?.velocity.dx ?? 0)
        } else if position.x > playableRect.maxX {
            node.position.x = playableRect.maxX
            node.physicsBody?.velocity.dx = min(0, node.physicsBody?.velocity.dx ?? 0)
        }
        
        if position.y < playableRect.minY {
            node.position.y = playableRect.minY
            node.physicsBody?.velocity.dy = max(0, node.physicsBody?.velocity.dy ?? 0)
        } else if position.y > playableRect.maxY {
            node.position.y = playableRect.maxY
            node.physicsBody?.velocity.dy = min(0, node.physicsBody?.velocity.dy ?? 0)
        }
    }
}

// Helper extension for distance calculation
extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        return sqrt(pow(point.x - x, 2) + pow(point.y - y, 2))
    }
}

extension CGRect {
    init(center: CGPoint, size: CGSize) {
        self.init(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}
