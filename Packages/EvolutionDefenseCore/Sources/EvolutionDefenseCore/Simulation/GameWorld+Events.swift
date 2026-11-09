// Optional random events every 3–4 waves (MatchOptions.randomEvents).
// They are rolled when a preparation phase starts and affect the coming wave.
// Negative events are mild and never stack, so they can't cause unavoidable losses.

/// The event affecting the coming / running wave.
public struct ActiveEvent: Codable, Sendable, Equatable {
    public var id: String
    public var text: String
    /// Pad of the broken-down tower or of the reinforcement.
    public var targetSlot: Int?
    public var reinforcement: TowerArchetype?
    public var reinforcementLevel: Int?
}

extension GameWorld {

    public var activeEventDefinition: RandomEventDefinition? { activeEvent.flatMap { config.event($0.id) } }

    var activeMutation: RandomEventDefinition? {
        guard let d = activeEventDefinition, d.kind == .mutation else { return nil }
        return d
    }

    func rollRandomEventIfDue(afterWave n: Int) {
        guard options.randomEvents, n >= nextEventWave, waves.hasNextWave, !config.events.isEmpty else { return }
        let s = config.rules.randomEvents
        nextEventWave = n + Int.random(in: s.minGap...s.maxGap, using: &eventRNG)
        var pool = config.events
        while !pool.isEmpty {
            let total = pool.reduce(0) { $0 + $1.weight }
            var pick = Double.random(in: 0..<total, using: &eventRNG)
            var index = 0
            for (i, e) in pool.enumerated() { pick -= e.weight; if pick < 0 { index = i; break } }
            if apply(pool[index], wave: n) { return }
            pool.remove(at: index)   // not applicable right now (e.g. no free pad) → try another
        }
    }

    /// Applies an event. Returns false if it can't happen in the current state.
    @discardableResult
    func apply(_ def: RandomEventDefinition, wave n: Int) -> Bool {
        var event = ActiveEvent(id: def.id, text: def.summary)
        func fill(_ key: String, _ value: String) { event.text = event.text.replacingOccurrences(of: "{\(key)}", with: value) }
        switch def.kind {
        case .gold:
            let gold = Int((def.value + (def.perWave ?? 0) * Double(n)).rounded())
            economy.earn(gold)
            stats.goldEarned += gold
            fill("gold", "\(gold)")
        case .researchDiscount:
            researchDiscount += Int(def.value)
            fill("rp", "\(Int(def.value))")
        case .mutation:
            break   // read by spawnEnemy while the event is active
        case .breakdown:
            let candidates = towers.filter { !$0.isTemporary }
            guard let t = candidates.randomElement(using: &eventRNG) else { return false }
            t.eventSpeedFactor = def.value
            t.refreshStats(modifiers)
            event.targetSlot = t.slotID
            fill("tower", "Your \(t.name)")
        case .reinforcement:
            let free = config.map.buildSlots.filter { towersBySlot[$0.id] == nil }
            guard let slot = free.randomElement(using: &eventRNG),
                  let archetype = TowerArchetype.allCases.randomElement(using: &eventRNG) else { return false }
            let era = waves.nextWave?.era ?? currentEra
            let level = min(config.tower(archetype).maxLevel, era.rawValue + 1)
            let t = placeTemporaryTower(archetype, level: level, slot: slot)
            event.targetSlot = slot.id
            event.reinforcement = archetype
            event.reinforcementLevel = level
            fill("tower", t.name)
        }
        activeEvent = event
        stats.randomEvents += 1
        events.append(.randomEvent(def, text: event.text))
        return true
    }

    @discardableResult
    func placeTemporaryTower(_ a: TowerArchetype, level: Int, slot: BuildSlotDefinition) -> Tower {
        let t = Tower(id: makeID(), slotID: slot.id, definition: config.tower(a), position: config.map.slotPosition(slot),
                      modifiers: modifiers)
        t.isTemporary = true
        t.level = level
        t.totalInvested = 0
        t.refreshStats(modifiers)
        towers.append(t)
        towersBySlot[slot.id] = t
        events.append(.towerBuilt(t))
        return t
    }

    /// Ends the effects that only last for one wave.
    func endWaveEvent() {
        guard let e = activeEvent else { return }
        if let def = config.event(e.id) {
            switch def.kind {
            case .breakdown:
                if let slot = e.targetSlot, let t = towersBySlot[slot] {
                    t.eventSpeedFactor = 1
                    t.refreshStats(modifiers)
                }
            case .reinforcement:
                if let slot = e.targetSlot, let t = towersBySlot[slot], t.isTemporary {
                    towersBySlot[slot] = nil
                    towers.removeAll { $0 === t }
                    t.target = nil
                    events.append(.towerRemoved(t))
                }
            case .gold, .researchDiscount, .mutation:
                break
            }
        }
        activeEvent = nil
    }

    /// Tools/tests: trigger a specific event now (preparation phase).
    @discardableResult
    public func debugTriggerEvent(_ id: String) -> Bool {
        guard phase == .preparation, let def = config.event(id) else { return false }
        endWaveEvent()
        return apply(def, wave: max(1, waveNumber))
    }
}
