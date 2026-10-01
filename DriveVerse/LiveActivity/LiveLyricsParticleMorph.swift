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
