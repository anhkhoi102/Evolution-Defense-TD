import Foundation

/// How a finished match is rated, from game.json → "stars".
/// A match is rated once, when it is won: 1 star for winning, more for keeping the base safe.
/// The rating looks at all the base HP lost during the match (repairs don't undo it).
public struct StarRatingConfig: Codable, Sendable, Equatable {
    /// Most base HP, as a fraction of the base's maximum, that may be lost in the whole match for 3 stars.
    public var threeStarMaxDamageFraction: Double
    /// The same for 2 stars.
    public var twoStarMaxDamageFraction: Double

    public init(threeStarMaxDamageFraction: Double = 0.2, twoStarMaxDamageFraction: Double = 0.5) {
        self.threeStarMaxDamageFraction = threeStarMaxDamageFraction
        self.twoStarMaxDamageFraction = twoStarMaxDamageFraction
    }

    /// Stars for winning a match after losing `damage` base HP in total.
    public func stars(damage: Int, maxBaseHP: Int) -> Int {
        if Double(damage) <= Double(maxBaseHP) * threeStarMaxDamageFraction { return 3 }
        if Double(damage) <= Double(maxBaseHP) * twoStarMaxDamageFraction { return 2 }
        return 1
    }

    public static let maxStars = 3
}
