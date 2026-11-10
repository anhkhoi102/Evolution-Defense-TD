import CoreGraphics

// Enemy abilities (regen, sprint, stealth, shields, summons, tower disables,
// missile strikes), boss phases, and status effects from tower hits.
extension GameWorld {

    func updateEnemyAbilities(_ dt: Double) {
        // Index loop: abilities may append (summons) and the new enemies start next step.
        let count = enemies.count
        var i = 0
        while i < count {
            let e = enemies[i]
            i += 1
            guard e.isActive else { continue }

            // Status effects
            if e.slowAmount > 0 && time >= e.slowUntil { e.slowAmount = 0 }
            if e.burnDPS > 0 {
                if time >= e.burnUntil {
                    e.burnDPS = 0
                } else {
                    applyDamage(to: e, raw: e.burnDPS * dt, penetration: 0, source: nil,
                                ignoreDefences: true, countsAsHit: false)
                    guard e.isActive else { continue }
                }
            }

            let a = e.abilities
            if let r = a.regen, e.hp < e.maxHP, time - e.lastDamageTime >= r.delayAfterHit {
                e.hp = min(e.maxHP, e.hp + r.perSecond * dt)
            }
            if let s = a.shield, e.shieldHP < e.maxShieldHP, time - e.lastDamageTime >= s.rechargeDelay {
                e.shieldHP = min(e.maxShieldHP, e.shieldHP + s.rechargePerSecond * dt)
            }
            if let s = a.stealth {
                e.stealthTimer -= dt
                if e.stealthTimer <= 0 {
                    e.isCloaked.toggle()
                    e.stealthTimer += e.isCloaked ? s.hidden : s.visible
                }
            }
            if let s = a.sprint {
                e.sprintTimer -= dt
                if e.sprintTimer <= 0 {
                    e.isSprinting.toggle()
                    e.sprintTimer += e.isSprinting ? s.duration : s.cooldown
                }
            }
            if let h = a.healAura {
                e.healTimer -= dt
                if e.healTimer <= 0 {
                    e.healTimer += h.interval
                    let r2 = CGFloat(h.radius * h.radius)
                    var healed = 0
                    for o in enemies where o !== e && o.isActive && !o.isBoss && o.burnDPS == 0 && o.hp < o.maxHP
                        && time - o.lastHealedTime >= h.interval * 0.9 {   // one heal per interval, however many healers
                        let dx = o.position.x - e.position.x, dy = o.position.y - e.position.y
                        guard dx * dx + dy * dy <= r2 else { continue }
                        o.hp = min(o.maxHP, o.hp + o.maxHP * h.fraction)
                        o.lastHealedTime = time
                        healed += 1
                    }
                    events.append(.enemiesHealed(by: e, ability: h.name, count: healed, radius: h.radius))
                }
            }
            if let s = a.summon {
                e.summonTimer -= dt
                if e.summonTimer <= 0 {
                    e.summonTimer += s.interval
                    for k in 0..<s.count {
                        spawnEnemy(s.enemy, atDistance: e.distance - 24 - CGFloat(k) * 14, minion: true)
                    }
                    events.append(.enemiesSummoned(by: e, ability: s.name, count: s.count))
                }
            }
            if let d = a.disableTowers {
                e.disableTimer -= dt
                if e.disableTimer <= 0 {
                    e.disableTimer += d.interval
                    disableTowers(near: e, d)
                }
            }
            if let b = a.baseStrike {
                e.strikeTimer -= dt
                if e.strikeTimer <= 0 {
                    e.strikeTimer += b.interval
                    let lost = damageBase(b.damage)
                    waves.recordBaseDamage(lost)
                    events.append(.baseStruck(by: e, ability: b.name, damage: lost))
                    if phase == .defeat { return }
                }
            }

            // Final speed for this step.
            var sp = e.baseSpeed
            if e.isSprinting, let s = a.sprint { sp *= s.multiplier }
            if e.slowAmount > 0 { sp *= 1 - e.slowAmount }
            if time < e.stunnedUntil { sp = 0 }
            e.speed = sp
        }
    }

    /// Knocks out the towers closest to `e` within the ability radius.
    private func disableTowers(near e: Enemy, _ d: DisableTowersAbility) {
        let r2 = CGFloat(d.radius * d.radius)
        scratchTowers.removeAll(keepingCapacity: true)
        for t in towers where t.position.distanceSquared(to: e.position) <= r2 {
            scratchTowers.append(t)
        }
        guard !scratchTowers.isEmpty else { return }
        scratchTowers.sort { $0.position.distanceSquared(to: e.position) < $1.position.distanceSquared(to: e.position) }
        let hit = Array(scratchTowers.prefix(max(1, d.maxTowers)))
        for t in hit {
            t.disabledUntil = max(t.disabledUntil, time + d.duration)
            t.target = nil
        }
        events.append(.towersDisabled(hit, by: e, ability: d.name, duration: d.duration))
    }

    /// Boss phase transitions and brood spawns after damage.
    func checkPhaseAndBrood(_ e: Enemy) {
        let phases = e.definition.sortedPhases
        if !phases.isEmpty {
            while e.phaseIndex + 1 < phases.count && e.hpFraction < phases[e.phaseIndex + 1].belowHP {
                enterPhase(e, index: e.phaseIndex + 1, phases[e.phaseIndex + 1])
            }
        }
        if let b = e.abilities.brood, b.everyHPFraction > 0 {
            let step = e.maxHP * b.everyHPFraction
            var spawned = 0
            while e.hp <= e.nextBroodHP && e.nextBroodHP > 0 && spawned < b.count * 3 {
                for k in 0..<b.count {
                    spawnEnemy(b.enemy, atDistance: e.distance - 18 - CGFloat(k) * 9, minion: true)
                }
                spawned += b.count
                e.nextBroodHP -= step
            }
            if spawned > 0 { events.append(.enemiesSummoned(by: e, ability: b.name, count: spawned)) }
        }
    }

    private func enterPhase(_ e: Enemy, index: Int, _ p: BossPhase) {
        e.phaseIndex = index
        if let armor = p.armor { e.armor = armor }
        e.baseSpeed = e.definition.speed * e.speedModifier * (p.speedMultiplier ?? 1)
        e.abilities = e.abilities.merged(with: p.abilities)
        e.configureAbilityTimers()
        events.append(.enemyPhaseChanged(e, name: p.name))
    }
}
