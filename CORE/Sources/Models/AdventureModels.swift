import Foundation

// MARK: - Enemies

struct Enemy: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: EnemyKind
    var health: Int
    var maxHealth: Int
    var attack: Int
    var isBoss: Bool

    init(kind: EnemyKind, playerLevel: Int) {
        self.id = UUID()
        self.kind = kind
        self.isBoss = kind == .shrineWarden
        let scale = 1.0 + Double(playerLevel - 1) * 0.15
        self.maxHealth = Int(Double(kind.baseHealth) * scale)
        self.health = maxHealth
        self.attack = Int(Double(kind.baseAttack) * scale)
    }
}

/// MVP enemy roster: 3–5 enemy types plus one boss.
enum EnemyKind: String, Codable, CaseIterable {
    case mosskit        // small, easy
    case emberling      // quick attacker
    case stonehusk      // slow, tanky
    case riftling       // rare, drops extra fragments
    case shrineWarden   // the Meadow's boss — guards the second Core

    var displayName: String {
        switch self {
        case .mosskit:      return "Mosskit"
        case .emberling:    return "Emberling"
        case .stonehusk:    return "Stonehusk"
        case .riftling:     return "Riftling"
        case .shrineWarden: return "Shrine Warden"
        }
    }

    var baseHealth: Int {
        switch self {
        case .mosskit:      return 30
        case .emberling:    return 40
        case .stonehusk:    return 70
        case .riftling:     return 45
        case .shrineWarden: return 160
        }
    }

    var baseAttack: Int {
        switch self {
        case .mosskit:      return 4
        case .emberling:    return 7
        case .stonehusk:    return 5
        case .riftling:     return 6
        case .shrineWarden: return 10
        }
    }

    var xpReward: Int {
        switch self {
        case .mosskit:      return 20
        case .emberling:    return 30
        case .stonehusk:    return 45
        case .riftling:     return 40
        case .shrineWarden: return 150
        }
    }

    /// Seconds between enemy attacks.
    var attackInterval: TimeInterval {
        switch self {
        case .mosskit:      return 3.5
        case .emberling:    return 2.2
        case .stonehusk:    return 4.0
        case .riftling:     return 2.8
        case .shrineWarden: return 2.5
        }
    }
}

// MARK: - Items & fragments

enum ItemKind: String, Codable, CaseIterable {
    case berry          // restores creature health at camp
    case charm          // small permanent happiness boost
    case relicShard     // collectible secret

    var displayName: String {
        switch self {
        case .berry:      return "Sunberry"
        case .charm:      return "Meadow Charm"
        case .relicShard: return "Relic Shard"
        }
    }
}

// MARK: - The Meadow

/// The compact first world. Sections unlock gradually.
enum MeadowZone: String, Codable, CaseIterable {
    case camp
    case forest
    case ruins
    case caveEntrance
    case coreShrine

    var displayName: String {
        switch self {
        case .camp:         return "Camp"
        case .forest:       return "Forest"
        case .ruins:        return "Ruins"
        case .caveEntrance: return "Cave Entrance"
        case .coreShrine:   return "Core Shrine"
        }
    }

    /// Level required before the zone appears on the adventure map.
    var unlockLevel: Int {
        switch self {
        case .camp:         return 1
        case .forest:       return 1
        case .ruins:        return 3
        case .caveEntrance: return 5
        case .coreShrine:   return 6
        }
    }
}

// MARK: - Frozen adventure state

/// When Adventure Time reaches zero the game state is preserved, not reset.
/// Whatever the player was doing remains available for the next session.
struct AdventureSnapshot: Codable, Equatable {
    var zone: MeadowZone
    /// Enemy mid-fight when time ran out, if any.
    var activeEnemy: Enemy?
    /// Creature health at freeze time.
    var creatureHealth: Int
    var frozenAt: Date
}

/// Summary shown at the end of a session ("Adventure complete").
struct AdventureSummary: Codable, Equatable {
    var enemiesDefeated: Int = 0
    var xpEarned: Int = 0
    var fragmentsFound: [String: Int] = [:]   // core rawValue -> count
    var itemsFound: [String: Int] = [:]       // item rawValue -> count
    var secondsPlayed: Int = 0
    var levelsGained: Int = 0
}
