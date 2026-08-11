import Foundation
import Combine

/// Runs one Adventure session in real time: the countdown, the scripted
/// flow of encounters and discoveries, simple real-time combat, and the
/// freeze when time reaches zero.
@MainActor
final class AdventureEngine: ObservableObject {

    enum Phase: Equatable {
        case exploring
        case somethingNearby(String)          // "Something is nearby…"
        case combat(Enemy)
        case choice(Enemy)                    // larger enemy: Fight or Explore
        case discovery(DiscoveryReward)
        case frozen                           // time ran out mid-adventure
        case complete                         // player left at camp cleanly
    }

    struct DiscoveryReward: Equatable {
        var title: String
        var fragmentCore: ElementalCore?
        var fragmentCount: Int
        var item: ItemKind?
    }

    enum PlayerAction {
        case tapAttack
        case swipeDodge
        case ability
    }

    // MARK: Published state

    @Published private(set) var secondsRemaining: Int
    @Published private(set) var phase: Phase = .exploring
    @Published private(set) var creatureHealth: Int
    @Published private(set) var summary = AdventureSummary()
    @Published private(set) var abilityCooldownRemaining: TimeInterval = 0
    @Published private(set) var eventLog: [String] = []
    /// One-shot combat feedback for the UI ("MISS", "-12", "Shield!").
    @Published var combatFlash: String?

    private(set) var creature: Creature
    private let gameState: GameState
    private var timer: AnyCancellable?
    private var enemyAttackCountdown: TimeInterval = 0
    private var nextEventCountdown: TimeInterval
    private var dodgeWindowUntil: Date?
    private var shieldActive = false
    private let bossAvailable: Bool
    private var bossSpawned = false

    /// Called with the final creature + summary + optional frozen snapshot.
    var onEnd: ((Creature, AdventureSummary, AdventureSnapshot?) -> Void)?

    init(creature: Creature, gameState: GameState, secondsAvailable: Int) {
        self.creature = creature
        self.gameState = gameState
        self.secondsRemaining = secondsAvailable
        self.creatureHealth = creature.health
        self.nextEventCountdown = TimeInterval(Int.random(in: 12...25))
        // The boss guards the shrine; it appears once the player has
        // nearly completed a second Core.
        self.bossAvailable = gameState.completedUnclaimedCore != nil
            || ElementalCore.allCases.contains {
                !creature.cores.contains($0) && gameState.fragmentCount(for: $0) >= Tuning.fragmentsPerCore - 2
            }

        // Resume a frozen adventure exactly where it stopped.
        if let frozen = gameState.frozenAdventure {
            self.creatureHealth = max(frozen.creatureHealth, 30)   // creatures rest overnight
            if let enemy = frozen.activeEnemy {
                self.phase = .combat(enemy)
                self.enemyAttackCountdown = enemy.kind.attackInterval
                log("The \(enemy.kind.displayName) is still here…")
            } else {
                log("You return to where you left off.")
            }
        } else {
            log("\(creature.name) steps into the Meadow.")
        }
    }

    // MARK: - Session lifecycle

    func start() {
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    /// Player chose to leave early (only offered while exploring).
    func leaveAdventure() {
        end(frozen: nil)
    }

    private func tick() {
        guard secondsRemaining > 0 else { return }
        secondsRemaining -= 1
        summary.secondsPlayed += 1
        abilityCooldownRemaining = max(0, abilityCooldownRemaining - 1)

        if secondsRemaining == 0 {
            freeze()
            return
        }

        switch phase {
        case .combat(let enemy):
            tickCombat(enemy: enemy)
        case .exploring:
            nextEventCountdown -= 1
            if nextEventCountdown <= 0 { spawnEvent() }
        default:
            break
        }
    }

    /// Adventure Time reached zero: the game state is preserved, not
    /// reset. Whatever the player was doing awaits the next session.
    private func freeze() {
        let activeEnemy: Enemy?
        if case .combat(let enemy) = phase { activeEnemy = enemy } else { activeEnemy = nil }
        phase = .frozen
        let snapshot = AdventureSnapshot(
            zone: .forest,
            activeEnemy: activeEnemy,
            creatureHealth: creatureHealth,
            frozenAt: Date()
        )
        end(frozen: snapshot)
    }

    private func end(frozen: AdventureSnapshot?) {
        timer?.cancel()
        timer = nil
        creature.health = creatureHealth
        if frozen == nil { phase = .complete }
        onEnd?(creature, summary, frozen)
    }

    // MARK: - Event scripting

    private func spawnEvent() {
        nextEventCountdown = TimeInterval(Int.random(in: 15...30))

        // The boss takes priority when its conditions are met and there's
        // enough time to plausibly fight it.
        if bossAvailable, secondsRemaining > 75, !bossSpawned {
            bossSpawned = true
            beginEncounter(Enemy(kind: .shrineWarden, playerLevel: creature.level), asChoice: true)
            return
        }

        switch Int.random(in: 0..<10) {
        case 0..<4:
            let kind: EnemyKind = [.mosskit, .emberling, .stonehusk].randomElement() ?? .mosskit
            beginEncounter(Enemy(kind: kind, playerLevel: creature.level), asChoice: false)
        case 4..<6:
            let big: EnemyKind = Bool.random() ? .stonehusk : .riftling
            beginEncounter(Enemy(kind: big, playerLevel: creature.level), asChoice: true)
        default:
            phase = .somethingNearby("\(creature.name) senses something nearby…")
            log("Something is nearby…")
        }
    }

    private func beginEncounter(_ enemy: Enemy, asChoice: Bool) {
        if asChoice {
            phase = .choice(enemy)
            log("A \(enemy.kind.displayName) blocks the path!")
        } else {
            phase = .combat(enemy)
            enemyAttackCountdown = enemy.kind.attackInterval
            log("A \(enemy.kind.displayName) appears!")
        }
    }

    /// Player follows the "something nearby" prompt.
    func investigate() {
        guard case .somethingNearby = phase else { return }
        phase = .discovery(rollDiscovery())
    }

    func chooseFight() {
        guard case .choice(let enemy) = phase else { return }
        phase = .combat(enemy)
        enemyAttackCountdown = enemy.kind.attackInterval
    }

    func chooseExplore() {
        guard case .choice = phase else { return }
        log("\(creature.name) slips away quietly.")
        phase = .exploring
        nextEventCountdown = 8
    }

    func collectDiscovery() {
        guard case .discovery(let reward) = phase else { return }
        if let core = reward.fragmentCore, reward.fragmentCount > 0 {
            summary.fragmentsFound[core.rawValue, default: 0] += reward.fragmentCount
            log("Found \(core.symbol) \(core.displayName) Fragment ×\(reward.fragmentCount)!")
        }
        if let item = reward.item {
            summary.itemsFound[item.rawValue, default: 0] += 1
            log("Found a \(item.displayName)!")
        }
        phase = .exploring
    }

    private func rollDiscovery() -> DiscoveryReward {
        // Bias fragments toward the Core the player is closest to
        // completing, so progress feels directed.
        let missing = ElementalCore.allCases.filter { !creature.cores.contains($0) }
        let targetCore = missing.max { gameState.fragmentCount(for: $0) < gameState.fragmentCount(for: $1) }
            ?? .crystal
        let roll = Int.random(in: 0..<10)
        switch roll {
        case 0..<6:
            return DiscoveryReward(title: "A hidden chest!", fragmentCore: targetCore, fragmentCount: 1, item: nil)
        case 6..<8:
            return DiscoveryReward(title: "Berries in the undergrowth", fragmentCore: nil, fragmentCount: 0, item: .berry)
        default:
            return DiscoveryReward(title: "A gleam among the ruins", fragmentCore: targetCore, fragmentCount: 2, item: nil)
        }
    }

    // MARK: - Combat

    /// Tap = attack, swipe = dodge, hold = Core ability.
    /// Combat must be understandable within seconds.
    func perform(_ action: PlayerAction) {
        guard case .combat(var enemy) = phase else { return }

        switch action {
        case .tapAttack:
            let damage = creature.stats.attack + Int.random(in: -2...3)
            enemy.health -= max(1, damage)
            combatFlash = "-\(max(1, damage))"

        case .swipeDodge:
            // Opens a short window during which the next enemy attack misses.
            dodgeWindowUntil = Date().addingTimeInterval(1.2)
            combatFlash = "Dodge!"

        case .ability:
            guard abilityCooldownRemaining <= 0, let core = creature.cores.first else { return }
            let ability = core.ability
            abilityCooldownRemaining = ability.cooldown
            switch core {
            case .crystal:
                shieldActive = true
                combatFlash = "Shield!"
            case .aqua:
                let heal = 20 + creature.level * 2
                creatureHealth = min(creature.stats.maxHealth, creatureHealth + heal)
                combatFlash = "+\(heal)"
            default:
                let damage = Int(Double(creature.stats.attack) * ability.damageMultiplier) + Int.random(in: 0...4)
                enemy.health -= max(1, damage)
                combatFlash = "\(ability.name)! -\(max(1, damage))"
            }
        }

        if enemy.health <= 0 {
            defeat(enemy)
        } else {
            phase = .combat(enemy)
        }
    }

    private func tickCombat(enemy: Enemy) {
        enemyAttackCountdown -= 1
        guard enemyAttackCountdown <= 0 else { return }
        enemyAttackCountdown = enemy.kind.attackInterval

        if let window = dodgeWindowUntil, window > Date() {
            combatFlash = "MISS"
            dodgeWindowUntil = nil
            return
        }
        if shieldActive {
            shieldActive = false
            combatFlash = "Blocked!"
            return
        }

        let damage = max(1, enemy.attack - creature.stats.defence / 4 + Int.random(in: -1...2))
        creatureHealth = max(0, creatureHealth - damage)
        combatFlash = "\(creature.name) -\(damage)"

        // Defeat is a setback, never a death: the creature withdraws and
        // the enemy wanders off.
        if creatureHealth == 0 {
            creatureHealth = 15
            phase = .exploring
            nextEventCountdown = 20
            log("\(creature.name) retreats to catch its breath…")
        }
    }

    private func defeat(_ enemy: Enemy) {
        summary.enemiesDefeated += 1
        let xp = enemy.kind.xpReward
        summary.xpEarned += xp
        summary.levelsGained += creature.gainXP(xp)
        log("\(enemy.kind.displayName) defeated! +\(xp) XP")

        // Enemies drop fragments; the boss drops a burst of them.
        let missing = ElementalCore.allCases.filter { !creature.cores.contains($0) }
        if let target = missing.max(by: { gameState.fragmentCount(for: $0) < gameState.fragmentCount(for: $1) }) {
            let drop = enemy.isBoss ? 3 : (Int.random(in: 0..<3) == 0 ? 1 : 0)
            if drop > 0 {
                summary.fragmentsFound[target.rawValue, default: 0] += drop
                log("It dropped \(target.symbol) Fragment ×\(drop)!")
            }
        }

        phase = .exploring
        nextEventCountdown = TimeInterval(Int.random(in: 10...20))
    }

    // MARK: - Helpers

    private func log(_ message: String) {
        eventLog.append(message)
        if eventLog.count > 6 { eventLog.removeFirst() }
    }

    var formattedTime: String {
        String(format: "%d:%02d", secondsRemaining / 60, secondsRemaining % 60)
    }
}
