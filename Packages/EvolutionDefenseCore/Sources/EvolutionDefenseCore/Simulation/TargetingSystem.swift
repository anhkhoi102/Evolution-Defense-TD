import CoreGraphics

/// Pure target selection. Allocation-free: a single pass over the enemy list.
public enum TargetingSystem {

    /// Whether `enemy` is a legal target for a tower at `position`.
    @inline(__always)
    public static func isValid(_ enemy: Enemy, from position: CGPoint, rangeSquared: CGFloat,
                               canTargetAir: Bool, detectsStealth: Bool = false) -> Bool {
        enemy.isActive
            && (canTargetAir || !enemy.isFlying)
            && (detectsStealth || !enemy.isCloaked)
            && enemy.position.distanceSquared(to: position) <= rangeSquared
    }

    public static func selectTarget(
        from enemies: [Enemy],
        towerPosition: CGPoint,
        range: CGFloat,
        priority: TargetingPriority,
        canTargetAir: Bool,
        detectsStealth: Bool = false
    ) -> Enemy? {
        let rangeSq = range * range
        var best: Enemy?
        var bestScore = -CGFloat.greatestFiniteMagnitude
        var bestTieBreak = -CGFloat.greatestFiniteMagnitude
        var bestBoss: Enemy?
        var bestBossProgress = -CGFloat.greatestFiniteMagnitude

        for e in enemies where isValid(e, from: towerPosition, rangeSquared: rangeSq,
                                       canTargetAir: canTargetAir, detectsStealth: detectsStealth) {
            // (score, tieBreak): higher is better. Ties go to the enemy furthest along.
            let score: CGFloat
            switch priority {
            case .first, .boss: score = e.distance
            case .last: score = -e.distance
            case .strongest: score = CGFloat(e.hp + e.shieldHP)
            case .weakest: score = -CGFloat(e.hp + e.shieldHP)
            case .closest: score = -e.position.distanceSquared(to: towerPosition)
            }
            let tie = e.distance
            if score > bestScore || (score == bestScore && tie > bestTieBreak) {
                bestScore = score; bestTieBreak = tie; best = e
            }
            if priority == .boss && e.isBoss && e.distance > bestBossProgress {
                bestBossProgress = e.distance
                bestBoss = e
            }
        }
        // Boss priority falls back to First when no boss is in range.
        return bestBoss ?? best
    }
}

public enum DamageModel {
    /// Resistance (a percentage for the damage type) applies first, then flat
    /// armor with a guaranteed minimum fraction. Makes rapid-fire weak vs armor
    /// and heavy towers strong — by design.
    public static func effectiveDamage(raw: Double, armor: Double, penetration: Double, minimumFraction: Double,
                                       resistance: Double = 0) -> Double {
        let resisted = raw * (1 - min(0.9, max(0, resistance)))
        let effectiveArmor = max(0, armor - penetration)
        return max(resisted * minimumFraction, resisted - effectiveArmor)
    }
}
