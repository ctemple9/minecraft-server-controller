import SwiftUI
import SpriteKit
#if os(macOS)
import AppKit
#endif

final class RunnerScene: SKScene {

    // ─── Background & ground ───────────────────────────────────────────
    private var groundSegments: [SKNode] = []
    private var currentBackgroundColor: SKColor = SKColor(red: 0.75, green: 0.35, blue: 0.98, alpha: 1)

    func setBackgroundColor(_ color: SKColor) {
        currentBackgroundColor = color
        backgroundColor = color
        rebuildCloudColors()
    }

    // ─── Physics constants ─────────────────────────────────────────────
    private let groundY: CGFloat     = 3.0
    private let steveBaseY: CGFloat  = 3.0      // feet sit on groundY
    private let steveHeight: CGFloat = 20.0     // total sprite height

    // Gravity & jump — tuned so auto-jump guarantee is clean
    private let gravity: CGFloat        = -900.0
    private let jumpPeakOffset: CGFloat = 36.0  // height above ground to peak
    private lazy var jumpVelocity: CGFloat = sqrt(2 * abs(gravity) * jumpPeakOffset)

    // ─── Runner state ──────────────────────────────────────────────────
    private var runnerNode = SKNode()
    private var legsNode: SKNode?          // animated legs sub-node
    private var runnerVelocityY: CGFloat = 0
    private var isOnGround: Bool = true
    private var isFlashing: Bool = false   // hit-flash state

    // Squash/stretch scale targets
    private var scaleXTarget: CGFloat = 1.0
    private var scaleYTarget: CGFloat = 1.0

    // ─── Scrolling ─────────────────────────────────────────────────────
    private let scrollSpeed: CGFloat = 90.0
    private var lastUpdateTime: TimeInterval = 0

    // ─── Obstacle spawning ─────────────────────────────────────────────
    private var obstacleNodes: [SKNode] = []
    private var obstacleSpawnTimer: TimeInterval = 0
    private var nextSpawnInterval: TimeInterval = 3.0

    // ─── Score ─────────────────────────────────────────────────────────
    private var scoreNode: SKLabelNode?
    private var score: Int = 0
    private var scoreTick: TimeInterval = 0

    // ─── Auto-jump ─────────────────────────────────────────────────────
    private var autoJumpEnabled: Bool = true

    // ─── Parallax clouds ───────────────────────────────────────────────
    private var cloudNodes: [SKNode] = []
    private let cloudCount = 4
    private let cloudScrollSpeed: CGFloat = 28.0  // ~30% of ground speed

    // ─── Setup flag ────────────────────────────────────────────────────
    private var didSetup = false

    // ──────────────────────────────────────────────────────────────────
    // MARK: didMove

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        guard !didSetup else { return }
        didSetup = true

        backgroundColor = currentBackgroundColor
        setupGround()
        setupClouds()
        setupRunner()
        setupScore()

        nextSpawnInterval = TimeInterval.random(in: 2.8...5.0)
        autoJumpEnabled = true
    }

    // ──────────────────────────────────────────────────────────────────
    // MARK: Ground

    private func setupGround() {
        groundSegments.forEach { $0.removeFromParent() }
        groundSegments.removeAll()

        // Dirt strip (brown) under the grass line — gives Minecraft ground depth
        for i in 0..<2 {
            let dirtH: CGFloat = 5.0
            let dirt = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size.width, height: dirtH))
            dirt.fillColor = SKColor(red: 0.42, green: 0.27, blue: 0.14, alpha: 0.85)
            dirt.strokeColor = .clear
            dirt.position = CGPoint(x: CGFloat(i) * size.width, y: groundY - dirtH)
            addChild(dirt)
            groundSegments.append(dirt)
        }

        // Grass line on top
        for i in 0..<2 {
            let grassH: CGFloat = 3.0
            let grass = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size.width, height: grassH))
            grass.fillColor = SKColor(red: 0.29, green: 0.69, blue: 0.22, alpha: 1.0)
            grass.strokeColor = .clear
            grass.position = CGPoint(x: CGFloat(i) * size.width, y: groundY)
            addChild(grass)
            groundSegments.append(grass)
        }
    }

    // ──────────────────────────────────────────────────────────────────
    // MARK: Clouds (parallax)

    private func setupClouds() {
        cloudNodes.forEach { $0.removeFromParent() }
        cloudNodes.removeAll()

        let cloudY = size.height * 0.65
        let spacing = size.width / CGFloat(cloudCount)

        for i in 0..<cloudCount {
            let cloud = makeCloud()
            cloud.position = CGPoint(
                x: CGFloat(i) * spacing + CGFloat.random(in: 0...(spacing * 0.5)),
                y: cloudY + CGFloat.random(in: -6...6)
            )
            cloud.alpha = CGFloat.random(in: 0.18...0.35)
            addChild(cloud)
            cloudNodes.append(cloud)
        }
    }

    private func makeCloud() -> SKNode {
        let node = SKNode()
        // Three overlapping white rectangles = blocky Minecraft cloud
        let parts: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0, 3, 10, 5),
            (3, 0, 14, 6),
            (10, 2, 8, 5),
        ]
        for (x, y, w, h) in parts {
            let r = SKShapeNode(rect: CGRect(x: x, y: y, width: w, height: h))
            r.fillColor = .white
            r.strokeColor = .clear
            node.addChild(r)
        }
        return node
    }

    private func rebuildCloudColors() {
        // Clouds stay white; just a hook if needed later
    }

    // ──────────────────────────────────────────────────────────────────
    // MARK: Pixel-art Steve

    private func setupRunner() {
        runnerNode.removeAllChildren()
        runnerNode.removeFromParent()
        legsNode = nil

        runnerNode.position = CGPoint(
            x: size.width * 0.18,
            y: groundY + steveBaseY
        )
        addChild(runnerNode)

        // ── Pixel palette ──────────────────────────────────────────────
        let skinColor   = SKColor(red: 0.20, green: 0.13, blue: 0.08, alpha: 1) // dark brown skin
        let hairColor   = SKColor(red: 0.08, green: 0.05, blue: 0.03, alpha: 1) // near-black hair
        let eyeColor    = SKColor(red: 0.85, green: 0.75, blue: 0.60, alpha: 1) // light eyes for contrast
        let shirtColor  = SKColor(red: 0.15, green: 0.35, blue: 0.72, alpha: 1) // blue shirt
        let pantsColor  = SKColor(red: 0.28, green: 0.22, blue: 0.55, alpha: 1) // dark blue pants
        let shoeColor   = SKColor(red: 0.28, green: 0.18, blue: 0.10, alpha: 1) // dark brown shoes

        // Helper: add a colored rect pixel to a parent node
        func px(_ parent: SKNode, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: SKColor) {
            let s = SKShapeNode(rect: CGRect(x: x, y: y, width: w, height: h))
            s.fillColor = color
            s.strokeColor = .clear
            parent.addChild(s)
        }

        // ── Head (9x9, starts at body top = y:11) ─────────────────────
        //   Row by row from top (y=19) down
        let headBase: CGFloat = 11
        // Hair rows (top 3px)
        px(runnerNode, -4, headBase+6, 9, 3, hairColor)
        // Face rows
        px(runnerNode, -4, headBase+2, 9, 4, skinColor)
        // Eyes (2px wide, 2px tall at row headBase+4..5)
        px(runnerNode, -3, headBase+4, 2, 2, eyeColor)
        px(runnerNode,  1, headBase+4, 2, 2, eyeColor)
        // Chin row
        px(runnerNode, -4, headBase,   9, 2, skinColor)

        // ── Body / Shirt (10x7, y:4..10) ──────────────────────────────
        px(runnerNode, -5, 4, 10, 7, shirtColor)
        // Shirt detail: darker stripe down center
        let stripeColor = SKColor(red: 0.10, green: 0.26, blue: 0.60, alpha: 1)
        px(runnerNode, -1, 4, 2, 7, stripeColor)

        // ── Legs (animated sub-node, y:0..4) ──────────────────────────
        let legs = SKNode()
        legs.position = .zero
        // Left leg
        px(legs, -4, 0, 4, 4, pantsColor)
        // Right leg
        px(legs, 1,  0, 4, 4, pantsColor)
        // Shoes
        px(legs, -4, 0, 4, 1, shoeColor)
        px(legs,  1, 0, 4, 1, shoeColor)
        runnerNode.addChild(legs)
        legsNode = legs

        // ── Leg animation: alternating stride ─────────────────────────
        let strideForward = SKAction.moveBy(x: 0, y: 1, duration: 0.10)
        let strideBack    = SKAction.moveBy(x: 0, y: -1, duration: 0.10)
        let stride = SKAction.repeatForever(
            SKAction.sequence([strideForward, strideBack])
        )
        legs.run(stride, withKey: "stride")

        // ── Body bob ──────────────────────────────────────────────────
        let bobUp   = SKAction.moveBy(x: 0, y: 1.2, duration: 0.11)
        let bobDown = bobUp.reversed()
        let bob     = SKAction.repeatForever(SKAction.sequence([bobUp, bobDown]))
        runnerNode.run(bob, withKey: "bob")

        // Reset physics
        runnerVelocityY = 0
        isOnGround      = true
        isFlashing      = false
        runnerNode.xScale = 1.0
        runnerNode.yScale = 1.0
    }

    // ──────────────────────────────────────────────────────────────────
    // MARK: Score label

    private func setupScore() {
        scoreNode?.removeFromParent()
        let label = SKLabelNode(fontNamed: "Courier-Bold")
        label.fontSize    = 9
        label.fontColor   = SKColor.white.withAlphaComponent(0.55)
        label.horizontalAlignmentMode = .right
        label.verticalAlignmentMode   = .top
        label.position = CGPoint(x: size.width - 6, y: size.height - 4)
        label.zPosition = 10
        label.text = "0"
        addChild(label)
        scoreNode = label
        score = 0
    }

    // ──────────────────────────────────────────────────────────────────
    // MARK: Resize

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        setupGround()
        setupClouds()
        runnerNode.position = CGPoint(x: size.width * 0.18, y: groundY + steveBaseY)
        scoreNode?.position = CGPoint(x: size.width - 6, y: size.height - 4)
    }

    // ──────────────────────────────────────────────────────────────────
    // MARK: Input — user click disables auto-jump for this run

    func handleUserJumpInput() {
        autoJumpEnabled = false
        jumpIfPossible()
    }

    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        handleUserJumpInput()
    }
    #endif

    private func jumpIfPossible() {
        guard isOnGround else { return }
        isOnGround = false
        runnerVelocityY = jumpVelocity

        // Launch squash: squish wide, flat
        runnerNode.removeAction(forKey: "squash")
        runnerNode.xScale = 1.3
        runnerNode.yScale = 0.75
        let restoreScale = SKAction.group([
            SKAction.scaleX(to: 1.0, duration: 0.10),
            SKAction.scaleY(to: 1.0, duration: 0.10)
        ])
        runnerNode.run(restoreScale, withKey: "squash")
        // Pause bob mid-air — resume on land
        runnerNode.removeAction(forKey: "bob")
    }

    // ──────────────────────────────────────────────────────────────────
    // MARK: Game loop

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)

        let dt: TimeInterval = lastUpdateTime == 0 ? 0 : currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        let dtf = CGFloat(dt)
        guard dtf > 0 && dtf < 0.1 else { return }   // skip big gaps (e.g. first frame, backgrounded)

        scrollGround(delta: dtf)
        scrollClouds(delta: dtf)
        updateObstacles(delta: dt)
        updateRunnerPhysics(delta: dtf)
        updateSquashStretch(delta: dtf)
        maybeAutoJump()
        checkCollisions()
        updateScore(delta: dt)
    }

    // ──────────────────────────────────────────────────────────────────
    // MARK: Scrolling

    private func scrollGround(delta dt: CGFloat) {
        let dx = -scrollSpeed * dt
        for seg in groundSegments {
            seg.position.x += dx
            if seg.position.x <= -size.width {
                seg.position.x += size.width * 2
            }
        }
    }

    private func scrollClouds(delta dt: CGFloat) {
        let dx = -cloudScrollSpeed * dt
        for cloud in cloudNodes {
            cloud.position.x += dx
            if cloud.position.x < -30 {
                cloud.position.x = size.width + CGFloat.random(in: 0...20)
                cloud.position.y = size.height * 0.65 + CGFloat.random(in: -6...6)
                cloud.alpha = CGFloat.random(in: 0.18...0.35)
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────
    // MARK: Obstacles — pixel Creepers

    private func updateObstacles(delta dt: TimeInterval) {
        let dtf = CGFloat(dt)
        let dx  = -scrollSpeed * dtf

        obstacleNodes = obstacleNodes.filter { mob in
            mob.position.x += dx
            if mob.position.x > -24 { return true }
            mob.removeFromParent()
            return false
        }

        obstacleSpawnTimer += dt
        if obstacleSpawnTimer >= nextSpawnInterval {
            obstacleSpawnTimer = 0
            nextSpawnInterval  = TimeInterval.random(in: 2.8...5.2)
            if Double.random(in: 0...1) < 0.65 { spawnObstacle() }
        }
    }

    private func spawnObstacle() {
        // Randomly choose tall Creeper or wide stump
        let type = Int.random(in: 0...2)
        let mob: SKNode

        switch type {
        case 0:  mob = makeCreeperSprite()
        case 1:  mob = makeCactusSprite()
        default: mob = makeStumpSprite()
        }

        mob.position = CGPoint(x: size.width + 14, y: groundY + 2)
        addChild(mob)
        obstacleNodes.append(mob)
    }

    /// Pixel-art Creeper: classic green with dark eye/mouth pattern
    private func makeCreeperSprite() -> SKNode {
        let node = SKNode()
        let g  = SKColor(red: 0.20, green: 0.60, blue: 0.20, alpha: 1) // green body
        let dg = SKColor(red: 0.05, green: 0.28, blue: 0.05, alpha: 1) // dark green face marks
        let bg = SKColor(red: 0.10, green: 0.40, blue: 0.10, alpha: 1) // mid-green

        func px(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: SKColor) {
            let s = SKShapeNode(rect: CGRect(x: x, y: y, width: w, height: h))
            s.fillColor = c; s.strokeColor = .clear
            node.addChild(s)
        }

        // Body: 8 wide, 14 tall
        px(0,  0, 8, 14, g)

        // Legs: two darker legs at bottom
        px(0,  0, 3, 4, bg)
        px(5,  0, 3, 4, bg)

        // Face block starts at y=9 (top 5 rows = face)
        // Eyes (2x2 each)
        px(1, 10, 2, 2, dg)
        px(5, 10, 2, 2, dg)

        // Mouth: T-shape
        px(2,  8, 4, 2, dg)
        px(3,  6, 2, 2, dg)

        return node
    }

    /// Pixel-art cobblestone block: compact cube profile to preserve jump clearance
    private func makeCactusSprite() -> SKNode {
        let node = SKNode()
        let stone      = SKColor(red: 0.53, green: 0.53, blue: 0.55, alpha: 1)
        let lightStone = SKColor(red: 0.64, green: 0.64, blue: 0.66, alpha: 1)
        let darkStone  = SKColor(red: 0.37, green: 0.37, blue: 0.39, alpha: 1)
        let deeperDark = SKColor(red: 0.27, green: 0.27, blue: 0.29, alpha: 1)

        func px(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: SKColor) {
            let s = SKShapeNode(rect: CGRect(x: x, y: y, width: w, height: h))
            s.fillColor = c; s.strokeColor = .clear
            node.addChild(s)
        }

        // Keep this obstacle as a simple block-sized cube so jump timing stays effectively unchanged.
        // Main block: 10 wide, 10 tall
        px(0, 0, 10, 10, stone)

        // Top-row highlights
        px(1, 8, 3, 1, lightStone)
        px(5, 8, 2, 1, darkStone)
        px(7, 8, 2, 1, lightStone)

        // Upper middle breakup
        px(0, 6, 2, 2, darkStone)
        px(2, 6, 3, 2, lightStone)
        px(5, 6, 2, 2, stone)
        px(7, 6, 3, 2, darkStone)

        // Mid-row breakup
        px(1, 4, 2, 2, deeperDark)
        px(3, 4, 3, 2, stone)
        px(6, 4, 2, 2, lightStone)
        px(8, 4, 1, 2, darkStone)

        // Lower middle breakup
        px(0, 2, 3, 2, stone)
        px(3, 2, 2, 2, darkStone)
        px(5, 2, 3, 2, lightStone)
        px(8, 2, 2, 2, stone)

        // Bottom texture/shadow
        px(1, 0, 2, 1, darkStone)
        px(4, 0, 2, 1, deeperDark)
        px(7, 0, 2, 1, darkStone)

        return node
    }

    /// Pixel-art tree stump: wide and squat
    private func makeStumpSprite() -> SKNode {
        let node = SKNode()
        let wood  = SKColor(red: 0.48, green: 0.32, blue: 0.16, alpha: 1)
        let dark  = SKColor(red: 0.30, green: 0.18, blue: 0.08, alpha: 1)
        let ring  = SKColor(red: 0.55, green: 0.40, blue: 0.22, alpha: 1)

        func px(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: SKColor) {
            let s = SKShapeNode(rect: CGRect(x: x, y: y, width: w, height: h))
            s.fillColor = c; s.strokeColor = .clear
            node.addChild(s)
        }

        // Wide base: 12 wide, 8 tall
        px(0, 0, 12, 8, wood)
        // Top ring detail
        px(2, 6, 8, 2, ring)
        // Bark lines
        px(3, 0, 1, 6, dark)
        px(7, 0, 1, 6, dark)

        return node
    }

    // ──────────────────────────────────────────────────────────────────
    // MARK: Runner physics

    private func updateRunnerPhysics(delta dt: CGFloat) {
        guard !isOnGround else { return }

        runnerVelocityY += gravity * dt
        runnerNode.position.y += runnerVelocityY * dt

        let minY = groundY + steveBaseY
        if runnerNode.position.y <= minY {
            runnerNode.position.y = minY
            runnerVelocityY = 0
            isOnGround = true

            // Landing squash then spring back
            runnerNode.removeAction(forKey: "squash")
            runnerNode.xScale = 1.35
            runnerNode.yScale = 0.70
            let spring = SKAction.group([
                SKAction.sequence([
                    SKAction.scaleX(to: 0.92, duration: 0.07),
                    SKAction.scaleX(to: 1.0,  duration: 0.06)
                ]),
                SKAction.sequence([
                    SKAction.scaleY(to: 1.15, duration: 0.07),
                    SKAction.scaleY(to: 1.0,  duration: 0.06)
                ])
            ])
            runnerNode.run(spring, withKey: "squash")

            // Resume bob on land
            let bobUp   = SKAction.moveBy(x: 0, y: 1.2, duration: 0.11)
            let bobDown = bobUp.reversed()
            let bob     = SKAction.repeatForever(SKAction.sequence([bobUp, bobDown]))
            runnerNode.run(bob, withKey: "bob")
        }
    }

    private func updateSquashStretch(delta dt: CGFloat) {
        // Stretch vertically while rising, compress while falling
        guard !isOnGround else { return }
        if runnerVelocityY > 0 {
            // Rising: stretch tall
            let target: CGFloat = 1.18
            runnerNode.yScale += (target - runnerNode.yScale) * 0.15
            runnerNode.xScale += (0.88 - runnerNode.xScale) * 0.15
        } else {
            // Falling: compress slightly
            let target: CGFloat = 0.95
            runnerNode.yScale += (target - runnerNode.yScale) * 0.12
            runnerNode.xScale += (1.04 - runnerNode.xScale) * 0.12
        }
    }

    // ──────────────────────────────────────────────────────────────────
    // MARK: Auto-jump — frame-aware clearance check
    //
    // Intended behavior:
    // - Auto-jump is ON by default for a new run.
    // - A user click turns auto-jump OFF for that run only.
    // - On death/restart, auto-jump turns back ON.
    //
    // The old version used one generic trigger distance for every obstacle.
    // That can fail on wider or taller sprites. Here we evaluate the real
    // obstacle frame and only jump when a jump *right now* would keep Steve's
    // body above the obstacle through the horizontal overlap window.

    private func maybeAutoJump() {
        guard autoJumpEnabled, isOnGround else { return }

        let ahead = obstacleNodes.filter {
            let frame = $0.calculateAccumulatedFrame()
            return frame.maxX >= runnerNode.position.x
        }
        guard let nearest = ahead.min(by: {
            $0.calculateAccumulatedFrame().minX < $1.calculateAccumulatedFrame().minX
        }) else { return }

        if shouldAutoJumpNow(for: nearest) {
            jumpIfPossible()
        }
    }

    private func shouldAutoJumpNow(for obstacle: SKNode) -> Bool {
        let runnerFrame = runnerNode.calculateAccumulatedFrame().insetBy(dx: 2, dy: 1)
        let obstacleFrame = obstacle.calculateAccumulatedFrame().insetBy(dx: 1, dy: 0)

        // Ignore obstacles already overlapping or already behind Steve.
        guard obstacleFrame.maxX > runnerFrame.minX else { return false }
        guard obstacleFrame.minX > runnerFrame.maxX else { return false }

        let totalAirTime = 2.0 * jumpVelocity / abs(gravity)
        let previewWindow: CGFloat = totalAirTime + 0.20
        let horizontalInset: CGFloat = 2
        let verticalClearance: CGFloat = 3

        let sampleXs: [CGFloat] = [
            runnerFrame.maxX - horizontalInset,
            runnerFrame.midX,
            runnerFrame.minX + horizontalInset
        ]

        var earliestRelevantTime = CGFloat.greatestFiniteMagnitude

        for sampleX in sampleXs {
            let tStart = max(0, (obstacleFrame.minX - sampleX) / scrollSpeed)
            let tEnd = min(totalAirTime, (obstacleFrame.maxX - sampleX) / scrollSpeed)

            if tEnd < 0 || tStart > totalAirTime || tStart > tEnd {
                continue
            }

            earliestRelevantTime = min(earliestRelevantTime, tStart)

            let tMid = (tStart + tEnd) * 0.5
            let jumpYs = [jumpY(at: tStart), jumpY(at: tMid), jumpY(at: tEnd)]
            let requiredY = obstacleFrame.maxY + verticalClearance

            if jumpYs.contains(where: { $0 <= requiredY }) {
                return false
            }
        }

        guard earliestRelevantTime != CGFloat.greatestFiniteMagnitude else { return false }
        return earliestRelevantTime <= previewWindow
    }

    private func jumpY(at time: CGFloat) -> CGFloat {
        let startY = groundY + steveBaseY
        let t = max(0, min(time, 2.0 * jumpVelocity / abs(gravity)))
        return startY + (jumpVelocity * t) + (0.5 * gravity * t * t) + 1
    }

    // ──────────────────────────────────────────────────────────────────
    // MARK: Collisions — hit flash then restart

    private func checkCollisions() {
        guard !isFlashing else { return }  // grace period during flash

        let runnerFrame = runnerNode
            .calculateAccumulatedFrame()
            .insetBy(dx: 4, dy: 3)  // slightly more forgiving near-miss window

        for mob in obstacleNodes {
            let mobFrame = mob
                .calculateAccumulatedFrame()
                .insetBy(dx: 1, dy: 1)

            if runnerFrame.intersects(mobFrame) {
                hitFlashAndRestart()
                break
            }
        }
    }

    private func hitFlashAndRestart() {
        isFlashing = true

        // Flash red 3 times then restart
        let flashOn  = SKAction.colorize(with: .red, colorBlendFactor: 0.9, duration: 0.05)
        let flashOff = SKAction.colorize(with: .white, colorBlendFactor: 0.0, duration: 0.05)
        let flash3   = SKAction.repeat(SKAction.sequence([flashOn, flashOff]), count: 3)
        let reset    = SKAction.run { [weak self] in self?.restartMiniGame() }

        runnerNode.run(SKAction.sequence([flash3, reset]), withKey: "flash")
    }

    private func restartMiniGame() {
        obstacleNodes.forEach { $0.removeFromParent() }
        obstacleNodes.removeAll()

        obstacleSpawnTimer = 0
        nextSpawnInterval  = TimeInterval.random(in: 2.8...5.0)
        autoJumpEnabled    = true
        isFlashing         = false
        score              = 0
        scoreNode?.text    = "0"

        setupRunner()
    }

    // ──────────────────────────────────────────────────────────────────
    // MARK: Score

    private func updateScore(delta dt: TimeInterval) {
        // Score ticks while server is running
        scoreTick += dt
        if scoreTick >= 0.1 {
            scoreTick -= 0.1
            score += 1
            scoreNode?.text = "\(score)"
        }
    }
}

