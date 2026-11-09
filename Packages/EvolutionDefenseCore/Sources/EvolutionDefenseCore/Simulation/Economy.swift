import Foundation

/// The player's gold. All gold changes go through here so totals stay consistent
/// and spending can never drive the balance negative.
public struct Economy: Sendable, Equatable, Codable {
    public private(set) var gold: Int
    /// Gold gained from kills, wave rewards and bonuses (not refunds).
    public private(set) var totalEarned = 0
    /// Gold spent on building, upgrading and repairing.
    public private(set) var totalSpent = 0
    /// Gold returned by selling towers.
    public private(set) var totalRefunded = 0

    public init(startingGold: Int) {
        gold = max(0, startingGold)
    }

    public func canAfford(_ cost: Int) -> Bool { cost >= 0 && gold >= cost }

    /// Deducts `cost` if affordable. Returns false (and changes nothing) otherwise.
    @discardableResult
    public mutating func spend(_ cost: Int) -> Bool {
        guard canAfford(cost) else { return false }
        gold -= cost
        totalSpent += cost
        return true
    }

    public mutating func earn(_ amount: Int) {
        guard amount > 0 else { return }
        gold += amount
        totalEarned += amount
    }

    public mutating func refund(_ amount: Int) {
        guard amount > 0 else { return }
        gold += amount
        totalRefunded += amount
    }

    mutating func debugSet(_ value: Int) { gold = max(0, value) }
}
