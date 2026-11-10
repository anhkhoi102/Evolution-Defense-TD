import Foundation

/// Turns a wave definition into a timed queue of spawns.
public struct EnemySpawner: Sendable {
    public struct ScheduledSpawn: Sendable, Equatable {
        public var time: Double
        public var enemyID: String
        public var modifiers = SpawnModifiers()
    }

    public private(set) var schedule: [ScheduledSpawn] = []
    public private(set) var elapsed: Double = 0
    private var nextIndex = 0

    public init() {}

    public var isFinished: Bool { nextIndex >= schedule.count }
    public var remaining: Int { schedule.count - nextIndex }

    public mutating func load(_ wave: WaveDefinition) {
        var list: [ScheduledSpawn] = []
        list.reserveCapacity(wave.totalEnemies)
        for g in wave.groups {
            for i in 0..<max(0, g.count) {
                let mods = SpawnModifiers(hp: g.hpMultiplier ?? 1, speed: g.speedMultiplier ?? 1, armorBonus: g.armorBonus ?? 0,
                                          elite: g.elite ?? false)
                list.append(ScheduledSpawn(time: g.delay + Double(i) * g.interval, enemyID: g.enemy, modifiers: mods))
            }
        }
        // Stable sort keeps group order for simultaneous spawns.
        schedule = list.enumerated().sorted { a, b in
            a.element.time != b.element.time ? a.element.time < b.element.time : a.offset < b.offset
        }.map(\.element)
        elapsed = 0
        nextIndex = 0
    }

    /// Advances time and calls `spawn` for every enemy now due.
    public mutating func update(_ dt: Double, spawn: (ScheduledSpawn) -> Void) {
        elapsed += dt
        while nextIndex < schedule.count && schedule[nextIndex].time <= elapsed {
            spawn(schedule[nextIndex])
            nextIndex += 1
        }
    }
}
