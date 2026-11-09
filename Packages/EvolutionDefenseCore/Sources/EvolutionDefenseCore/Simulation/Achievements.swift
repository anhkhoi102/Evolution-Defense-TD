extension Difficulty: Comparable {
    var rank: Int {
        switch self {
        case .easy: 0
        case .normal: 1
        case .hard: 2
        }
    }
    public static func < (a: Difficulty, b: Difficulty) -> Bool { a.rank < b.rank }
}

/// Checks achievement conditions against a match. Pure: the app keeps the
/// unlocked set in the player profile and asks which ones are newly met.
public enum AchievementEvaluator {

    public static func isMet(_ a: AchievementDefinition, in w: GameWorld) -> Bool {
        if let required = a.difficulty, w.options.difficulty < required { return false }
        let v = a.value ?? 0
        let won = w.phase == .victory
        let s = w.stats
        switch a.kind {
        case .win: return won
        case .killBoss: return s.bossesKilled.contains(a.target ?? "")
        case .towerLevel: return w.towers.contains { !$0.isTemporary && Double($0.level) >= v }
        case .allArchetypesAtLevel:
            return TowerArchetype.allCases.allSatisfy { arch in
                w.towers.contains { !$0.isTemporary && $0.archetype == arch && Double($0.level) >= v }
            }
        case .techsResearched: return Double(s.techsResearched) >= v
        case .winWithoutTech: return won && s.techsResearched == 0
        case .goldEarned: return Double(s.goldEarned) >= v
        case .perfectEra:
            return Era.allCases.contains { era in
                let count = w.config.waves.filter { $0.era == era }.count
                return count > 0 && s.perfectWavesByEra[era.rawValue - 1] >= count
            }
        case .winUnderSeconds: return won && w.time < v
        case .kills: return Double(s.enemiesKilled) >= v
        case .winWithHPAtMost: return won && Double(w.baseHP) <= v
        case .winWithoutLeaks: return won && s.enemiesLeaked == 0
        case .reachEra: return Double(s.highestEra) >= v
        }
    }

    /// Achievements met in this match that aren't in `unlocked` yet.
    public static func newlyMet(in w: GameWorld, unlocked: Set<String>) -> [AchievementDefinition] {
        w.config.achievements.filter { !unlocked.contains($0.id) && isMet($0, in: w) }
    }
}
