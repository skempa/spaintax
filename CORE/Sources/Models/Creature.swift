import Foundation

/// The player's permanent companion.
struct Creature: Codable, Equatable {
    var name: String
    var createdAt: Date
    var appearance: CreatureAppearance
    var analysis: DrawingAnalysis

    /// Cores collected, in acquisition order. The first is AI-assigned.
    var cores: [ElementalCore]

    var level: Int
    var xp: Int
    /// 0–100. Reduced by taking hits in combat; restored over time and by Aqua.
    var health: Int
    /// 0–100. Driven by the player's real-world behaviour and play.
    var happiness: Int
    var condition: CreatureCondition

    init(name: String, appearance: CreatureAppearance, analysis: DrawingAnalysis, firstCore: ElementalCore) {
        self.name = name
        self.createdAt = Date()
        self.appearance = appearance
        self.analysis = analysis
        self.cores = [firstCore]
        self.level = 1
        self.xp = 0
        self.health = 100
        self.happiness = 80
        self.condition = .normal
    }

    // MARK: - Evolution

    /// Three major evolution stages. Evolution is predictable: players
    /// should understand what collecting another Core will do.
    var evolutionStage: EvolutionStage {
        switch cores.count {
        case ..<2: return .origin      // Stage 1 — the original AI-created creature
        case 2..<4: return .awakened   // Stage 2 — triggered by a second Core
        default: return .ascended      // Stage 3 — significant Core milestone (4+)
        }
    }

    // MARK: - Stats

    var baseStats: CreatureStats {
        CreatureStats(
            attack: 8 + level * 2,
            defence: 4 + level,
            speed: 5 + level,
            maxHealth: 90 + level * 10
        )
    }

    /// Effective stats: base + Core bonuses, scaled by condition.
    var stats: CreatureStats {
        var s = cores.reduce(baseStats) { $0 + $1.statBonus }
        let m = condition.statMultiplier
        s.attack = Int(Double(s.attack) * m)
        s.defence = Int(Double(s.defence) * m)
        s.speed = Int(Double(s.speed) * m)
        return s
    }

    var xpForNextLevel: Int { 100 + (level - 1) * 80 }

    /// Grants XP (scaled by condition) and applies level-ups.
    /// Returns the number of levels gained.
    @discardableResult
    mutating func gainXP(_ amount: Int) -> Int {
        var gained = Int(Double(amount) * condition.xpMultiplier)
        gained = max(gained, 1)
        xp += gained
        var levelsGained = 0
        while xp >= xpForNextLevel {
            xp -= xpForNextLevel
            level += 1
            levelsGained += 1
        }
        return levelsGained
    }

    mutating func acquire(core: ElementalCore) {
        guard !cores.contains(core) else { return }
        cores.append(core)
    }

    var hasAllCores: Bool { cores.count == ElementalCore.allCases.count }
}

enum EvolutionStage: Int, Codable, Comparable {
    case origin = 1
    case awakened = 2
    case ascended = 3

    var displayName: String {
        switch self {
        case .origin:   return "Origin"
        case .awakened: return "Awakened"
        case .ascended: return "Ascended"
        }
    }

    static func < (lhs: EvolutionStage, rhs: EvolutionStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The creature's persistent condition, driven by the player's real-world
/// behaviour. Effects are always recoverable — one bad day never
/// permanently ruins progress.
enum CreatureCondition: String, Codable, CaseIterable {
    case energised
    case happy
    case normal
    case tired
    case weak

    var displayName: String {
        switch self {
        case .energised: return "Energised"
        case .happy:     return "Happy"
        case .normal:    return "Normal"
        case .tired:     return "Tired"
        case .weak:      return "Weak"
        }
    }

    var statMultiplier: Double {
        switch self {
        case .energised: return 1.15
        case .happy:     return 1.05
        case .normal:    return 1.0
        case .tired:     return 0.9
        case .weak:      return 0.75
        }
    }

    var xpMultiplier: Double {
        switch self {
        case .energised: return 1.25
        case .happy:     return 1.1
        case .normal:    return 1.0
        case .tired:     return 0.8
        case .weak:      return 0.6
        }
    }

    /// Message shown at camp, e.g. "Milo is recovering."
    func campMessage(name: String, improving: Bool) -> String {
        switch self {
        case .energised: return "\(name) is energised and ready for adventure!"
        case .happy:     return "\(name) is happy to see you."
        case .normal:    return "\(name) is doing fine."
        case .tired:     return improving ? "\(name) is recovering." : "\(name) seems tired today."
        case .weak:      return improving ? "\(name) is slowly recovering…" : "\(name) is feeling weak."
        }
    }
}
