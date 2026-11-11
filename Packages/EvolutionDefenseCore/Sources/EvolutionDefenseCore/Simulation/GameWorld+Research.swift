// Technology tree. Research Points come from bosses, era completion and
// perfect waves; tech is optional and can be bought at any time.
extension GameWorld {

    public func isResearched(_ id: String) -> Bool { researchedTechs.contains(id) }

    /// The already researched technology that shares `tech`'s doctrine group, if any.
    public func chosenDoctrine(excluding tech: TechDefinition) -> TechDefinition? {
        guard let g = tech.group else { return nil }
        return config.techs.first { $0.group == g && $0.id != tech.id && isResearched($0.id) }
    }

    /// RP price right now (Technology Boost discounts the next purchase, minimum 1).
    public func researchCost(_ tech: TechDefinition) -> Int { max(1, tech.cost - researchDiscount) }

    public func techStatus(_ tech: TechDefinition) -> TechStatus {
        if isResearched(tech.id) { return .researched }
        if tech.era > currentEra { return .locked(requires: tech.era) }
        if let other = chosenDoctrine(excluding: tech) { return .excluded(by: other.name) }
        let cost = researchCost(tech)
        if research < cost { return .unaffordable(needed: cost) }
        return .available
    }

    @discardableResult
    public func research(_ id: String) -> ResearchResult {
        if phase.isOver { return .matchOver }
        guard let tech = config.tech(id) else { return .unknownTech }
        if isResearched(id) { return .alreadyResearched }
        if tech.era > currentEra { return .eraLocked(requires: tech.era) }
        if let other = chosenDoctrine(excluding: tech) { return .excluded(by: other.name) }
        let cost = researchCost(tech)
        guard research >= cost else { return .insufficientResearch(needed: cost, available: research) }
        research -= cost
        researchDiscount = 0
        researchedTechs.append(id)
        stats.techsResearched += 1

        let oldBonus = modifiers.maxBaseHPBonus
        modifiers = TechModifiers(techs: researchedTechs.compactMap { config.tech($0) })
        let hpGain = modifiers.maxBaseHPBonus - oldBonus
        if hpGain > 0 {
            maxBaseHP += hpGain
            baseHP += hpGain
        }
        for t in towers {
            t.refreshStats(modifiers)
            t.retargetTimer = 0
        }
        events.append(.techResearched(tech))
        return .success(cost: cost)
    }
}
