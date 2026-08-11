import SwiftUI

/// The six elemental Cores. Cores are game mechanics only — they do not
/// represent real-world personality or behaviour.
enum ElementalCore: String, Codable, CaseIterable, Identifiable {
    case ember
    case crystal
    case storm
    case aqua
    case verdant
    case void

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ember:   return "Ember"
        case .crystal: return "Crystal"
        case .storm:   return "Storm"
        case .aqua:    return "Aqua"
        case .verdant: return "Verdant"
        case .void:    return "Void"
        }
    }

    /// The Core's identity, as shown to the player.
    var identity: String {
        switch self {
        case .ember:   return "Power"
        case .crystal: return "Defence"
        case .storm:   return "Speed"
        case .aqua:    return "Adaptation"
        case .verdant: return "Growth"
        case .void:    return "Control"
        }
    }

    var symbol: String {
        switch self {
        case .ember:   return "🔥"
        case .crystal: return "💎"
        case .storm:   return "⚡"
        case .aqua:    return "💧"
        case .verdant: return "🌿"
        case .void:    return "🌀"
        }
    }

    var color: Color {
        switch self {
        case .ember:   return Color(red: 0.95, green: 0.35, blue: 0.15)
        case .crystal: return Color(red: 0.55, green: 0.80, blue: 0.95)
        case .storm:   return Color(red: 0.95, green: 0.85, blue: 0.25)
        case .aqua:    return Color(red: 0.20, green: 0.55, blue: 0.90)
        case .verdant: return Color(red: 0.30, green: 0.75, blue: 0.35)
        case .void:    return Color(red: 0.55, green: 0.30, blue: 0.80)
        }
    }

    /// The primary ability granted by this Core.
    var ability: CoreAbility {
        switch self {
        case .ember:   return CoreAbility(name: "Flare Strike",   description: "A high-damage burst attack.",              damageMultiplier: 2.2, cooldown: 8)
        case .crystal: return CoreAbility(name: "Facet Shield",   description: "A shield that absorbs the next hit.",      damageMultiplier: 0.0, cooldown: 10)
        case .storm:   return CoreAbility(name: "Tempest Dash",   description: "A rapid dash that strikes twice.",         damageMultiplier: 1.4, cooldown: 6)
        case .aqua:    return CoreAbility(name: "Tidal Mend",     description: "Restores a portion of health.",            damageMultiplier: 0.0, cooldown: 12)
        case .verdant: return CoreAbility(name: "Rootcall",       description: "Summons vines that damage over time.",     damageMultiplier: 1.6, cooldown: 10)
        case .void:    return CoreAbility(name: "Blink Rift",     description: "Teleports behind the enemy, disrupting it.", damageMultiplier: 1.2, cooldown: 9)
        }
    }

    /// Passive stat bonuses applied while the creature holds this Core.
    var statBonus: CreatureStats {
        switch self {
        case .ember:   return CreatureStats(attack: 6, defence: 0, speed: 0, maxHealth: 0)
        case .crystal: return CreatureStats(attack: 0, defence: 6, speed: 0, maxHealth: 10)
        case .storm:   return CreatureStats(attack: 2, defence: 0, speed: 6, maxHealth: 0)
        case .aqua:    return CreatureStats(attack: 0, defence: 2, speed: 0, maxHealth: 15)
        case .verdant: return CreatureStats(attack: 2, defence: 2, speed: 0, maxHealth: 10)
        case .void:    return CreatureStats(attack: 3, defence: 0, speed: 4, maxHealth: 0)
        }
    }
}

struct CoreAbility: Codable, Equatable {
    let name: String
    let description: String
    /// Multiplier applied to the creature's base attack (0 = utility ability).
    let damageMultiplier: Double
    /// Cooldown in seconds during combat.
    let cooldown: TimeInterval
}

struct CreatureStats: Codable, Equatable {
    var attack: Int
    var defence: Int
    var speed: Int
    var maxHealth: Int

    static let zero = CreatureStats(attack: 0, defence: 0, speed: 0, maxHealth: 0)

    static func + (lhs: CreatureStats, rhs: CreatureStats) -> CreatureStats {
        CreatureStats(
            attack: lhs.attack + rhs.attack,
            defence: lhs.defence + rhs.defence,
            speed: lhs.speed + rhs.speed,
            maxHealth: lhs.maxHealth + rhs.maxHealth
        )
    }
}
