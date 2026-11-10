import CoreGraphics

// Summon abilities: temporary allied units (Call Militia, Summon Hero).
// Balance lives in summons.json; see Docs/SUMMONS.md for the rules.
//
// Summons reuse the existing systems: targets are checked with
// TargetingSystem.isValid (range, flying, stealth), damage goes through
// applyDamage (armor, resistances, shields, kills, gold), and time is the
// simulation clock (pause and game speed apply). Enemies are not changed:
// they keep walking, and only units they touch take contact damage.

public enum SummonResult: Equatable, Sendable {
    case success(units: Int)
    case unknownAbility
    case locked(unlockWave: Int)
    case onCooldown(remaining: Double)
    /// Summons are only for fights: they can't be called between waves.
    case notDuringWave
    /// Too far from the road, or outside the playfield.
    case invalidLocation
    case matchOver
}

/// What the UI needs to draw an ability button.
public struct SummonAbilityStatus: Sendable, Equatable {
    public var ability: SummonAbilityDefinition
    public var isUnlocked: Bool
    public var cooldownRemaining: Double
    /// Seconds until the deployed units vanish (0 when none are alive).
    public var activeRemaining: Double
    public var aliveUnits: Int
    /// Can be activated right now (unlocked, off cooldown, wave running, match not over).
    public var isReady: Bool

    public var cooldownFraction: Double {
        ability.cooldown > 0 ? min(1, cooldownRemaining / ability.cooldown) : 0
    }
}

extension GameWorld {

    // MARK: Queries

    public var summonAbilities: [SummonAbilityDefinition] { config.summons.abilities }

    public func summonStatus(_ id: String) -> SummonAbilityStatus? {
        guard let a = config.summons.ability(id) else { return nil }
        let unlocked = isSummonUnlocked(a)
        let cooldown = max(0, (summonReadyAt[id] ?? 0) - time)
        let alive = summons.filter { $0.ability.id == id && $0.isAlive }
        let active = alive.map { $0.remaining(at: time) }.max() ?? 0
        let ready = unlocked && cooldown <= 0 && phase == .waveInProgress
        return SummonAbilityStatus(ability: a, isUnlocked: unlocked, cooldownRemaining: cooldown,
                                   activeRemaining: active, aliveUnits: alive.count, isReady: ready)
    }

    /// Unlocked once its wave has been reached (the wave in progress, or the next one between waves).
    func isSummonUnlocked(_ a: SummonAbilityDefinition) -> Bool {
        let current = phase == .waveInProgress ? waveNumber : waveNumber + 1
        return current >= a.unlockWave
    }

    /// Where a summon clicked at `p` would stand: the point itself if it is on or
    /// beside the road and inside the playfield, otherwise nil.
    public func summonDeployPoint(near p: CGPoint) -> CGPoint? {
        let size = config.map.worldSize
        let margin: CGFloat = 12
        guard p.x >= margin, p.y >= margin, p.x <= size.width - margin, p.y <= size.height - margin else { return nil }
        let c = path.closestPoint(to: p)
        guard c.offset <= CGFloat(config.summons.maxDeployDistanceFromPath) else { return nil }
        // Not on the spawn stub outside the map or right on top of the base.
        guard c.alongPath > 40, c.alongPath < path.totalLength - 40 else { return nil }
        return p
    }

    // MARK: Activation

    /// Calls an ability's units at `point` (world coordinates).
    @discardableResult
    public func summon(_ id: String, at point: CGPoint) -> SummonResult {
        guard !phase.isOver else { return .matchOver }
        guard let a = config.summons.ability(id) else { return .unknownAbility }
        guard isSummonUnlocked(a) else { return .locked(unlockWave: a.unlockWave) }
        let cooldown = (summonReadyAt[id] ?? 0) - time
        guard cooldown <= 0 else { return .onCooldown(remaining: cooldown) }
        guard phase == .waveInProgress else { return .notDuringWave }
        guard let p = summonDeployPoint(near: point) else { return .invalidLocation }

        var units: [SummonUnit] = []
        for k in 0..<a.count {
            var pos = p
            if a.count > 1 {
                let angle = CGFloat(k) / CGFloat(a.count) * 2 * .pi + .pi / 4
                pos = CGPoint(x: p.x + cos(angle) * CGFloat(a.formationRadius),
                              y: p.y + sin(angle) * CGFloat(a.formationRadius))
            }
            let u = SummonUnit(id: makeID(), ability: a, at: pos, post: pos, time: time)
            units.append(u)
            summons.append(u)
        }
        summonReadyAt[id] = time + a.cooldown
        summonReadyAnnounced.remove(id)
        summonsCalled += 1
        events.append(.summonDeployed(a, units: units, at: p))
        return .success(units: units.count)
    }

    // MARK: Update

    func updateSummons(_ dt: Double) {
        announceReadySummons()
        guard !summons.isEmpty else { return }
        let contact = config.summons.contactDamage
        // Cloaked enemies need detection, as for towers: AI Targeting gives it to everyone.
        let detects = TowerArchetype.allCases.allSatisfy { modifiers.towers[$0]?.detectsStealth == true }

        for u in summons where u.isAlive {
            if time >= u.expiresAt {
                u.isAlive = false
                u.target = nil
                events.append(.summonExpired(u))
                continue
            }
            let s = u.stats
            u.attackCooldown = max(0, u.attackCooldown - dt)

            // Keep or find a target.
            if let t = u.target, !isValidSummonTarget(t, for: u, detects: detects) { u.target = nil }
            u.retargetTimer -= dt
            if u.target == nil || u.retargetTimer <= 0 {
                u.retargetTimer = 0.25
                u.target = bestSummonTarget(for: u, detects: detects) ?? u.target
            }

            if let t = u.target {
                let reach = CGFloat(s.range) + t.radius
                let d = u.position.distance(to: t.position)
                u.heading = (t.position - u.position).angle
                if d > reach {
                    moveSummon(u, toward: t.position, stopAt: reach * 0.9, dt: dt)
                    u.state = .moving
                } else {
                    u.state = .attacking
                    if u.attackCooldown <= 0 {
                        u.attackCooldown = 1 / s.attacksPerSecond
                        u.lastAttackTime = time
                        strike(t, by: u, raw: s.damage)
                        events.append(.summonAttacked(u, t))
                    }
                }
            } else if u.position.distance(to: u.post) > 4 {
                u.heading = (u.post - u.position).angle
                moveSummon(u, toward: u.post, stopAt: 0, dt: dt)
                u.state = .moving
            } else {
                u.state = .idle
            }

            // Special attack (hero): an area blow while fighting.
            if let sp = u.ability.special {
                u.specialTimer = max(0, u.specialTimer - dt)
                if u.specialTimer <= 0, u.state == .attacking {
                    let r2 = CGFloat(sp.radius * sp.radius)
                    var hits = 0
                    for e in enemies where e.isActive && (s.canTargetAir || !e.isFlying) && (detects || !e.isCloaked)
                        && e.position.distanceSquared(to: u.position) <= r2 {
                        strike(e, by: u, raw: sp.damage)
                        hits += 1
                    }
                    u.specialTimer = sp.interval
                    events.append(.summonSpecial(u, name: sp.name, radius: sp.radius, hits: hits))
                }
            }

            // Contact damage from enemies touching the unit (they don't stop walking).
            if contact.perBaseDamage > 0 {
                var dps = 0.0
                for e in enemies where e.isActive && !e.isFlying {
                    let touch = e.radius + CGFloat(s.radius)
                    if e.position.distanceSquared(to: u.position) <= touch * touch {
                        dps += min(contact.maxPerEnemy, Double(e.definition.baseDamage) * contact.perBaseDamage)
                    }
                }
                if dps > 0 {
                    u.hp -= dps * dt
                    u.lastHitTakenTime = time
                    if u.hp <= 0 {
                        u.hp = 0
                        u.isAlive = false
                        u.target = nil
                        events.append(.summonDefeated(u))
                    }
                }
            }
        }
        summons.removeAll { !$0.isAlive }
    }

    /// Removes every summoned unit (match over). Each gets an expiry event so views clean up.
    func dismissAllSummons() {
        for u in summons where u.isAlive {
            u.isAlive = false
            u.target = nil
            events.append(.summonExpired(u))
        }
        summons.removeAll()
    }

    // MARK: Helpers

    private func announceReadySummons() {
        for a in config.summons.abilities where !summonReadyAnnounced.contains(a.id) {
            guard isSummonUnlocked(a), (summonReadyAt[a.id] ?? 0) <= time else { continue }
            summonReadyAnnounced.insert(a.id)
            events.append(.summonReady(a))
        }
    }

    private func isValidSummonTarget(_ e: Enemy, for u: SummonUnit, detects: Bool) -> Bool {
        let s = u.stats
        guard e.isActive, s.canTargetAir || !e.isFlying, detects || !e.isCloaked else { return false }
        // Units hold their ground: they don't chase beyond their leash.
        return e.position.distanceSquared(to: u.post) <= CGFloat(s.leash * s.leash)
    }

    /// Minions take the nearest threat; heroes go for bosses, then elites, then the nearest enemy.
    private func bestSummonTarget(for u: SummonUnit, detects: Bool) -> Enemy? {
        let s = u.stats
        let aggro2 = CGFloat(s.aggroRange * s.aggroRange)
        var best: Enemy?
        var bestScore = -CGFloat.greatestFiniteMagnitude
        for e in enemies where TargetingSystem.isValid(e, from: u.post, rangeSquared: aggro2,
                                                       canTargetAir: s.canTargetAir, detectsStealth: detects) {
            var score = -e.position.distanceSquared(to: u.position)
            if u.isHero {
                if e.isBoss { score += 1e9 } else if e.isElite { score += 1e8 }
            }
            if score > bestScore { bestScore = score; best = e }
        }
        return best
    }

    private func moveSummon(_ u: SummonUnit, toward p: CGPoint, stopAt: CGFloat, dt: Double) {
        let d = u.position.distance(to: p)
        guard d > stopAt else { return }
        let step = min(d - stopAt, CGFloat(u.stats.moveSpeed * dt))
        let dir = (p - u.position) * (1 / max(d, 0.001))
        u.position = u.position + dir * step
    }

    private func strike(_ e: Enemy, by u: SummonUnit, raw: Double) {
        let before = e.hp + e.shieldHP
        applyDamage(to: e, raw: raw, penetration: u.stats.armorPenetration, type: u.stats.damageType, source: nil)
        u.damageDealt += max(0, before - max(0, e.hp) - e.shieldHP)
        if !e.isAlive { u.kills += 1 }
    }
}
