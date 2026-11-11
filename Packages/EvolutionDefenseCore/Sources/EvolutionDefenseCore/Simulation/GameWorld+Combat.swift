import CoreGraphics

// Towers, projectiles and damage.
extension GameWorld {

    // MARK: Towers

    func updateTowers(_ dt: Double) {
        for t in towers {
            let s = t.stats
            let range = CGFloat(s.range)
            t.cooldown -= dt
            t.retargetTimer -= dt
            if t.isDisabled(at: time) {
                t.target = nil
                t.cooldown = max(t.cooldown, 0)
                continue
            }
            if t.disabledDuration > 0 {          // the knock-out just ran out by itself
                endDisable(t)
                events.append(.towerRecovered(t, paid: 0))
            }
            let detects = s.seesStealth

            if let current = t.target,
               !TargetingSystem.isValid(current, from: t.position, rangeSquared: range * range,
                                        canTargetAir: s.canTargetAir, detectsStealth: detects) {
                t.target = nil
            }
            if t.target == nil || t.retargetTimer <= 0 {
                t.target = TargetingSystem.selectTarget(
                    from: enemies, towerPosition: t.position, range: range,
                    priority: t.targeting, canTargetAir: s.canTargetAir, detectsStealth: detects)
                t.retargetTimer = retargetInterval
            }

            guard let target = t.target else {
                t.cooldown = max(0, t.cooldown)   // ready to fire as soon as something arrives
                continue
            }
            t.aimAngle = (target.position - t.position).angle
            if t.focusTarget !== target { t.focusTarget = target; t.focusSince = time }
            if t.cooldown <= 0 {
                fire(t, at: target, stats: s)
                // Focus fire (technology): faster once it has stayed on one target for a while.
                let focus = modifiers.mods(for: t.archetype).focusFire
                let interval = focus > 0 && time - t.focusSince >= Self.focusFireDelay ? s.attackInterval / (1 + focus) : s.attackInterval
                t.cooldown = max(0, t.cooldown + interval)
            }
        }
    }

    static let focusFireDelay = 2.0
    /// An enemy cannot be stunned or frozen again for this long after one ends.
    static let controlImmunity = 4.0
    static let freezeImmunity = 6.0
    /// Slows needed within `freezeWindow` seconds to freeze.
    static let freezeHits = 3
    static let freezeWindow = 4.0
    static let interruptCooldown = 6.0
    static let healthyThreshold = 0.8
    /// Half the width of the line a piercing shot travels along.
    static let pierceHalfWidth: CGFloat = 14

    private func fire(_ t: Tower, at target: Enemy, stats s: TowerLevelStats) {
        let p = acquireProjectile()
        let hit = s.hitEffects
        var damage = s.damage
        p.isCritical = false
        if hit.critChance > 0 && Double.random(in: 0..<1, using: &rng) < hit.critChance {
            damage *= hit.critMultiplier
            p.isCritical = true
        }
        p.isActive = true
        p.kind = s.projectile
        p.visual = s.projectileAsset
        p.origin = t.position
        p.position = t.position
        p.target = target
        p.targetPoint = target.position
        p.speed = CGFloat(s.projectileSpeed)
        p.damage = damage
        p.aoeRadius = CGFloat(s.aoeRadius)
        p.armorPenetration = s.armorPenetration
        p.damageType = s.type
        p.hit = hit
        p.canHitAir = s.canTargetAir
        p.edgeDamage = s.aoeEdgeDamage ?? 1
        t.shotCount += 1
        p.chains = hit.chainEvery >= 1 && hit.chainTargets >= 1 && t.shotCount % Int(hit.chainEvery) == 0
        p.source = t
        p.travelled = 0
        p.plannedDistance = max(1, t.position.distance(to: target.position))
        p.heading = (target.position - t.position).angle
        t.lastFireTime = time
        events.append(.towerFired(t, p))
    }

    // MARK: Projectiles

    func updateProjectiles(_ dt: Double) {
        for p in projectiles where p.isActive {
            if let tgt = p.target {
                if tgt.isActive { p.targetPoint = tgt.position } else { p.target = nil }
            }
            let toTarget = p.targetPoint - p.position
            let dist = toTarget.length
            let stepLen = p.speed * CGFloat(dt)
            if dist <= stepLen || dist < 2 {
                p.position = p.targetPoint
                p.travelled += dist
                impact(p)
            } else {
                let dir = toTarget * (1 / dist)
                p.position += dir * stepLen
                p.travelled += stepLen
                p.heading = dir.angle
            }
        }
    }

    private func impact(_ p: Projectile) {
        var hit = false
        if p.aoeRadius > 0 {
            // Splash hits everything in the blast, cloaked enemies included.
            for e in enemies where e.isActive && (p.canHitAir || !e.isFlying) {
                let reach = p.aoeRadius + e.radius * 0.5
                let d2 = e.position.distanceSquared(to: p.position)
                if d2 <= reach * reach {
                    // Falloff: full damage in the inner half of the blast, down to `edgeDamage` at its edge.
                    var scale = 1.0
                    if p.edgeDamage < 1 {
                        let f = Double(d2.squareRoot() / p.aoeRadius)
                        scale = f <= 0.5 ? 1 : max(p.edgeDamage, 1 - (1 - p.edgeDamage) * (min(f, 1) - 0.5) / 0.5)
                    }
                    applyHit(p, to: e, scale: scale)
                    hit = true
                }
            }
            if p.hit.groundBurn > 0 && p.hit.groundDuration > 0, let t = p.source {
                let zone = BurnZone(towerID: t.id, position: p.position, radius: Double(p.aoeRadius) * 0.8,
                                    dps: p.damage * p.hit.groundBurn, until: time + p.hit.groundDuration, nextTick: time)
                if let i = burnZones.firstIndex(where: { $0.towerID == t.id }) { burnZones[i] = zone } else { burnZones.append(zone) }
                events.append(.groundFire(position: zone.position, radius: zone.radius, duration: p.hit.groundDuration))
            }
        } else if let tgt = p.target, tgt.isActive {
            applyHit(p, to: tgt)
            hit = true
        }
        events.append(.projectileImpact(kind: p.kind, position: p.position, aoeRadius: p.aoeRadius, hit: hit))
        releaseProjectile(p)
    }

    private func applyHit(_ p: Projectile, to e: Enemy, scale: Double = 1) {
        let h = p.hit
        let (damage, critical) = conditionalDamage(h, base: p.damage * scale, critical: p.isCritical, on: e)
        let centre = e.position
        applyDamage(to: e, raw: damage, penetration: p.armorPenetration, type: p.damageType, source: p.source, shieldBonus: h.shieldBonus)
        if critical { events.append(.criticalHit(e, damage: damage)) }
        if e.isActive { applyStatus(h, rawDamage: damage, to: e, source: p.source) }

        // Target painter (technology): the mark also lands on enemies right next to the target.
        if h.expose > 0 && modifiers.exposeRadius > 0 {
            let r2 = CGFloat(modifiers.exposeRadius * modifiers.exposeRadius)
            let mark = HitEffects(expose: h.expose, exposeDuration: h.exposeDuration)
            for o in enemies where o !== e && o.isActive && o.position.distanceSquared(to: centre) <= r2 {
                applyStatus(mark, rawDamage: 0, to: o, source: p.source)
            }
        }
        // Piercing shot: carries on in a straight line through the enemies behind the target.
        if h.pierceTargets >= 1 && p.aoeRadius == 0 {
            let along = centre - p.origin
            let len = along.length
            if len > 1 {
                let dir = along * (1 / len)
                var behind: [(Enemy, CGFloat)] = []
                for o in enemies where o !== e && o.isActive && (p.canHitAir || !o.isFlying) {
                    let rel = o.position - centre
                    let forward = rel.x * dir.x + rel.y * dir.y
                    guard forward > 0 && forward <= CGFloat(h.pierceLength) else { continue }
                    let side = abs(rel.x * dir.y - rel.y * dir.x)
                    if side <= Self.pierceHalfWidth + o.radius * 0.5 { behind.append((o, forward)) }
                }
                behind.sort { $0.1 < $1.1 }
                var last: CGPoint?
                for (o, _) in behind.prefix(Int(h.pierceTargets)) {
                    last = o.position
                    let through = damage * h.pierceDamage
                    applyDamage(to: o, raw: through, penetration: p.armorPenetration, type: p.damageType, source: p.source)
                    if o.isActive { applyStatus(h, rawDamage: through, to: o, source: p.source) }
                }
                if let last { events.append(.piercingShot(from: centre, to: last)) }
            }
        }
        // Chain lightning: jumps to the nearest other enemies, carrying the shot's effects.
        if p.chains {
            let r2 = CGFloat(h.chainRange * h.chainRange)
            var points = [centre]
            var struck: [Enemy] = []
            for _ in 0..<Int(h.chainTargets) {
                var best: Enemy?
                var bestD = r2
                for o in enemies where o !== e && o.isActive && (p.canHitAir || !o.isFlying) && !struck.contains(where: { $0 === o }) {
                    let d = o.position.distanceSquared(to: points[points.count - 1])
                    if d <= bestD { bestD = d; best = o }
                }
                guard let o = best else { break }
                struck.append(o)
                points.append(o.position)
                let jump = damage * h.chainDamage
                applyDamage(to: o, raw: jump, penetration: p.armorPenetration, type: p.damageType, source: p.source)
                if o.isActive { applyStatus(h, rawDamage: jump, to: o, source: p.source) }
            }
            if points.count > 1 { events.append(.chainLightning(points)) }
        }
    }

    /// Conditional bonuses (what makes a tower good at its own job): Execute on wounded targets,
    /// critical hits on Exposed ones, and the technology bonuses against afflicted or healthy enemies.
    func conditionalDamage(_ h: HitEffects, base: Double, critical: Bool = false, on e: Enemy) -> (damage: Double, critical: Bool) {
        var damage = base
        var critical = critical
        if h.execute > 0 && e.hpFraction < h.executeThreshold {
            damage *= 1 + (e.isBoss ? h.execute * 0.5 : h.execute)
            events.append(.statusApplied(e, .execute))
        }
        if h.exposedCritChance > 0 && !critical && e.isExposed && Double.random(in: 0..<1, using: &rng) < h.exposedCritChance {
            damage *= max(h.critMultiplier, 2)
            critical = true
        }
        if h.afflictedBonus > 0 && (e.isSlowed || e.isBurning) { damage *= 1 + h.afflictedBonus }
        if h.healthyBonus > 0 && e.hpFraction > Self.healthyThreshold { damage *= 1 + h.healthyBonus }
        return (damage, critical)
    }

    /// Burning ground: ground enemies standing in a fire keep burning.
    func updateBurnZones() {
        guard !burnZones.isEmpty else { return }
        burnZones.removeAll { time >= $0.until }
        for i in burnZones.indices where time >= burnZones[i].nextTick {
            burnZones[i].nextTick = time + 0.5
            let z = burnZones[i]
            let r2 = CGFloat(z.radius * z.radius)
            for e in enemies where e.isActive && !e.isFlying && e.position.distanceSquared(to: z.position) <= r2 {
                e.burnDPS = max(time < e.burnUntil ? e.burnDPS : 0, z.dps)
                e.burnUntil = max(e.burnUntil, time + 0.75)
            }
        }
    }

    /// Slow, burn and stun from a hit. Bosses shrug off stuns and take half the slow.
    func applyStatus(_ h: HitEffects, rawDamage: Double, to e: Enemy, source: Tower? = nil) {
        if h.slow > 0 && h.slowDuration > 0 && e.trait != .insulated {
            let amount = e.isBoss ? h.slow * 0.5 : h.slow
            if amount >= e.slowAmount || time >= e.slowUntil {
                e.slowAmount = amount
            }
            e.slowUntil = max(e.slowUntil, time + h.slowDuration)
            // Cryo shells (technology): enough slows in a short time freeze the enemy solid.
            if modifiers.freezeSeconds > 0 && !e.isBoss && time >= e.controlImmuneUntil {
                if time - e.slowHitsSince > Self.freezeWindow { e.slowHits = 0; e.slowHitsSince = time }
                e.slowHits += 1
                if e.slowHits >= Self.freezeHits {
                    e.slowHits = 0
                    e.frozenUntil = time + modifiers.freezeSeconds
                    e.stunnedUntil = max(e.stunnedUntil, e.frozenUntil)
                    e.controlImmuneUntil = e.frozenUntil + Self.freezeImmunity
                    events.append(.statusApplied(e, .freeze))
                }
            }
        }
        if h.burn > 0 && h.burnDuration > 0 {
            e.burnDPS = max(time < e.burnUntil ? e.burnDPS : 0, rawDamage * h.burn)
            e.burnUntil = time + h.burnDuration
        }
        if h.stun > 0 && !e.isBoss && time >= e.controlImmuneUntil {
            e.stunnedUntil = max(e.stunnedUntil, time + h.stun)
            e.controlImmuneUntil = e.stunnedUntil + Self.controlImmunity
        }
        // Interrupt: pushes a boss's next abilities back, at most once per cooldown.
        if h.interrupt > 0 && e.isBoss && time >= e.interruptReadyAt {
            e.interruptReadyAt = time + Self.interruptCooldown
            e.disableTimer += h.interrupt
            e.strikeTimer += h.interrupt
            e.summonTimer += h.interrupt
            events.append(.statusApplied(e, .interrupt))
        }
        // Armour Shred: one counter per enemy, shared by every tower that shreds. The cap is the
        // highest one that has hit it while the effect lasts; bosses lose at most half of that.
        if h.shred > 0 && h.shredDuration > 0 {
            let cap = e.isBoss || e.trait == .plated ? h.shredCap * 0.5 : h.shredCap
            e.shredCap = max(e.shredCap, cap)
            let was = e.shredAmount
            e.shredAmount = min(e.shredCap, e.armor, e.shredAmount + h.shred)
            e.shredUntil = time + h.shredDuration
            e.shredSource = source
            if was == 0 && e.shredAmount > 0 { events.append(.statusApplied(e, .shred)) }
        }
        // Expose: never stacks; the strongest mark wins and hits refresh it. Half as long on bosses.
        if h.expose > 0 && h.exposeDuration > 0 {
            let was = e.exposeAmount
            e.exposeAmount = max(e.exposeAmount, h.expose)
            e.exposeUntil = max(e.exposeUntil, time + (e.isBoss ? h.exposeDuration * 0.5 : h.exposeDuration))
            e.exposeSource = source
            if was == 0 { events.append(.statusApplied(e, .expose)) }
        }
    }

    // MARK: Damage

    /// Resistance → armor → energy shield → HP. `ignoreDefences` skips
    /// resistance and armor (burning) but shields still absorb it.
    func applyDamage(to e: Enemy, raw: Double, penetration: Double, type: DamageType = .physical,
                     source: Tower?, ignoreDefences: Bool = false, countsAsHit: Bool = true, shieldBonus: Double = 0) {
        guard e.isActive, raw > 0 else { return }
        if time < e.phasedUntil { return }          // phasing: nothing lands while it flickers out
        // Shred lowers armour; Expose raises what gets through. Burning (ignoreDefences) is unaffected by both.
        var dmg = raw
        if !ignoreDefences {
            let res = e.definition.resistance[type]
            let shredded = DamageModel.effectiveDamage(raw: raw, armor: e.effectiveArmor, penetration: penetration,
                                                       minimumFraction: minDamageFraction, resistance: res)
            dmg = shredded * (1 + e.exposeAmount)
            // Overpressure (technology): stunned or frozen enemies take more from everything.
            if modifiers.controlledBonus > 0 && time < e.stunnedUntil { dmg *= 1 + modifiers.controlledBonus }
            // Credit what the team effects added to the towers that applied them (statistics only).
            if e.shredAmount > 0, let t = e.shredSource {
                t.assistDamage += shredded - DamageModel.effectiveDamage(raw: raw, armor: e.armor, penetration: penetration,
                                                                         minimumFraction: minDamageFraction, resistance: res)
            }
            if e.exposeAmount > 0, let t = e.exposeSource { t.assistDamage += shredded * e.exposeAmount }
        }
        if e.shieldHP > 0 {
            // Energy weapons tear through shields 50 % faster.
            let mult = type == .energy ? 1.5 + shieldBonus : 1.0
            let absorbed = min(e.shieldHP, dmg * mult)
            e.shieldHP -= absorbed
            dmg -= absorbed / mult
        }
        if countsAsHit { e.lastHitTime = time }
        e.lastDamageTime = time
        guard dmg > 0 else { return }
        let dealt = min(dmg, e.hp)
        e.hp -= dmg
        source?.damageDealt += dealt
        if e.hp <= 0 {
            kill(e, source: source)
        } else {
            checkPhaseAndBrood(e)
        }
    }

    private func kill(_ e: Enemy, source: Tower?) {
        e.hp = 0
        e.isAlive = false
        let reward = Int((Double(e.definition.goldReward) * e.rewardMultiplier).rounded())
        economy.earn(reward)
        stats.goldEarned += reward
        stats.enemiesKilled += 1
        waves.recordKill(gold: reward)
        source?.kills += 1
        events.append(.enemyKilled(e, reward: reward))
        // Incendiary (technology): a burning enemy that dies sets its neighbours on fire.
        if modifiers.burnSpreadRadius > 0 && e.burnDPS > 0 && time < e.burnUntil {
            let r2 = CGFloat(modifiers.burnSpreadRadius * modifiers.burnSpreadRadius)
            for o in enemies where o !== e && o.isActive && o.position.distanceSquared(to: e.position) <= r2 {
                o.burnDPS = max(time < o.burnUntil ? o.burnDPS : 0, e.burnDPS)
                o.burnUntil = max(o.burnUntil, time + 2.5)
            }
        }
        if e.isBoss {
            stats.bossesDefeated += 1
            stats.bossesKilled.append(e.definition.id)
            // A battlefield's own boss also counts as the campaign boss it stands in for (achievements).
            if let campaign = config.campaignID(for: e.definition.id) { stats.bossesKilled.append(campaign) }
            if let rp = e.definition.researchReward, rp > 0 {
                addResearch(rp)
                waves.recordResearch(rp)
                events.append(.researchEarned(amount: rp, reason: "\(e.definition.displayName) defeated"))
            }
        }
        if let split = e.abilities.splitOnDeath, split.count > 0 {
            for i in 0..<split.count {
                spawnEnemy(split.enemy, atDistance: e.distance - CGFloat(i) * 10, minion: true)
            }
            events.append(.enemySplit(e, count: split.count))
        }
    }

    // MARK: Pool

    func acquireProjectile() -> Projectile {
        if freeProjectiles.isEmpty { growProjectilePool(by: 64) }
        return projectiles[freeProjectiles.removeLast()]
    }

    func releaseProjectile(_ p: Projectile) {
        p.isActive = false
        p.target = nil
        p.source = nil
        freeProjectiles.append(p.poolIndex)
    }

    func growProjectilePool(by n: Int) {
        let start = projectiles.count
        for i in start..<(start + n) {
            projectiles.append(Projectile(poolIndex: i))
            freeProjectiles.append(i)
        }
    }
}
