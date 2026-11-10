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
            if t.cooldown <= 0 {
                fire(t, at: target, stats: s)
                t.cooldown = max(0, t.cooldown + s.attackInterval)
            }
        }
    }

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
                if e.position.distanceSquared(to: p.position) <= reach * reach {
                    applyHit(p, to: e)
                    hit = true
                }
            }
        } else if let tgt = p.target, tgt.isActive {
            applyHit(p, to: tgt)
            hit = true
        }
        events.append(.projectileImpact(kind: p.kind, position: p.position, aoeRadius: p.aoeRadius, hit: hit))
        releaseProjectile(p)
    }

    private func applyHit(_ p: Projectile, to e: Enemy) {
        applyDamage(to: e, raw: p.damage, penetration: p.armorPenetration, type: p.damageType, source: p.source)
        if p.isCritical { events.append(.criticalHit(e, damage: p.damage)) }
        guard e.isActive else { return }
        applyStatus(p.hit, rawDamage: p.damage, to: e, source: p.source)
    }

    /// Slow, burn and stun from a hit. Bosses shrug off stuns and take half the slow.
    func applyStatus(_ h: HitEffects, rawDamage: Double, to e: Enemy, source: Tower? = nil) {
        if h.slow > 0 && h.slowDuration > 0 {
            let amount = e.isBoss ? h.slow * 0.5 : h.slow
            if amount >= e.slowAmount || time >= e.slowUntil {
                e.slowAmount = amount
            }
            e.slowUntil = max(e.slowUntil, time + h.slowDuration)
        }
        if h.burn > 0 && h.burnDuration > 0 {
            e.burnDPS = max(time < e.burnUntil ? e.burnDPS : 0, rawDamage * h.burn)
            e.burnUntil = time + h.burnDuration
        }
        if h.stun > 0 && !e.isBoss {
            e.stunnedUntil = max(e.stunnedUntil, time + h.stun)
        }
        // Armour Shred: one counter per enemy, shared by every tower that shreds. The cap is the
        // highest one that has hit it while the effect lasts; bosses lose at most half of that.
        if h.shred > 0 && h.shredDuration > 0 {
            let cap = e.isBoss ? h.shredCap * 0.5 : h.shredCap
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
                     source: Tower?, ignoreDefences: Bool = false, countsAsHit: Bool = true) {
        guard e.isActive, raw > 0 else { return }
        // Shred lowers armour; Expose raises what gets through. Burning (ignoreDefences) is unaffected by both.
        var dmg = raw
        if !ignoreDefences {
            let res = e.definition.resistance[type]
            let shredded = DamageModel.effectiveDamage(raw: raw, armor: e.effectiveArmor, penetration: penetration,
                                                       minimumFraction: minDamageFraction, resistance: res)
            dmg = shredded * (1 + e.exposeAmount)
            // Credit what the team effects added to the towers that applied them (statistics only).
            if e.shredAmount > 0, let t = e.shredSource {
                t.assistDamage += shredded - DamageModel.effectiveDamage(raw: raw, armor: e.armor, penetration: penetration,
                                                                         minimumFraction: minDamageFraction, resistance: res)
            }
            if e.exposeAmount > 0, let t = e.exposeSource { t.assistDamage += shredded * e.exposeAmount }
        }
        if e.shieldHP > 0 {
            // Energy weapons tear through shields 50 % faster.
            let mult = type == .energy ? 1.5 : 1.0
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
