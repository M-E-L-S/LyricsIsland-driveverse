import Foundation

/// MELS homepage: spring=2.4, damping=0.85; particle-object.js converts these
/// to stiffness=60*spring and velocity decay=3+12*damping for mass=1.
enum LiveLyricsParticlePhysics {
    static let mass = 1.0
    static let stiffness = 144.0
    static let damping = 13.2
    static let settlingDuration: TimeInterval = 1.2

    /// Fixed hash instead of Math.random: the same cloud must be identical
    /// when a separate extension process archives a non-lyric update.
    static func randomUnit(index: Int, salt: UInt64) -> Double {
        var value = UInt64(index) &+ salt &+ 0x9e3779b97f4a7c15
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        value ^= value >> 31
        return Double(value >> 11) / 9_007_199_254_740_992
    }
}

struct LiveLyricsParticleMorphPlan: Equatable {
    let revision: Int
    let previousText: String?
    let animates: Bool
}

/// The homepage pairs homes by spatial rank. Match bounded bitmap cohorts
/// the same way; every displacement ends at ink in the other lyric, never at
/// an intermediate random scatter location.
struct LiveLyricsParticleHome: Equatable {
    let id: Int
    let x: Double
    let y: Double
}

struct LiveLyricsParticleDisplacement: Equatable {
    let x: Double
    let y: Double
    static let zero = Self(x: 0, y: 0)
}

enum LiveLyricsParticleRoutes {
    static func offsets(from homes: [LiveLyricsParticleHome],
                        to targets: [LiveLyricsParticleHome]) -> [Int: LiveLyricsParticleDisplacement] {
        func ordered(_ values: [LiveLyricsParticleHome]) -> [LiveLyricsParticleHome] {
            values.filter { $0.x.isFinite && $0.y.isFinite }.sorted {
                if $0.x != $1.x { return $0.x < $1.x }
                if $0.y != $1.y { return $0.y < $1.y }
                return $0.id < $1.id
            }
        }
        let source = ordered(homes)
        let destination = ordered(targets)
        guard !source.isEmpty, !destination.isEmpty else { return [:] }
        var result: [Int: LiveLyricsParticleDisplacement] = [:]
        for (rank, home) in source.enumerated() {
            let index = min(destination.count - 1,
                            ((2 * rank + 1) * destination.count) / (2 * source.count))
            let target = destination[index]
            result[home.id] = .init(x: target.x - home.x, y: target.y - home.y)
        }
        return result
    }
}

/// The homepage's lyric-change handler compares text, not line indices. Keep
/// this ledger independent of the Activity policy/reset and marquee phases.
struct LiveLyricsParticleMorphTracker {
    private var text: String?
    private var revision = 0

    mutating func prepare(text incoming: String, animate: Bool) -> LiveLyricsParticleMorphPlan {
        guard incoming != text else {
            return LiveLyricsParticleMorphPlan(revision: revision, previousText: nil, animates: false)
        }
        let outgoing = text
        text = incoming
        revision += 1
        let animates = animate && outgoing?.isEmpty == false && !incoming.isEmpty
        return LiveLyricsParticleMorphPlan(
            revision: revision, previousText: animates ? outgoing : nil, animates: animates
        )
    }
}
