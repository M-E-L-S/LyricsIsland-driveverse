#if canImport(ActivityKit) && canImport(WidgetKit)
import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents
#if canImport(UIKit)
import UIKit
#endif

@main
struct DriveVerseWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LyricsLiveActivity()
    }
}

struct LyricsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsAttributes.self) { context in
            // Lock screen — on iOS 26 this same presentation is shown on the
            // CarPlay screen, so it stays high-contrast and sparse:
            // one small meta row and two text rows.
            LockScreenLyricsView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center, priority: 1) {
                    HStack(alignment: .center, spacing: 12) {
                        ActivityArtwork(data: context.state.artworkData, size: 52)
                        VStack(alignment: .leading, spacing: 5) {
                            LiveLineText(state: context.state)
                                .font(.title3.bold())
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)
                            Text(context.state.secondaryLine.isEmpty
                                 ? context.state.nextLine
                                 : context.state.secondaryLine)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LivePlaybackControls(isPlaying: context.state.isPlaying)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                ActivityArtwork(data: context.state.artworkData, size: 22)
            } compactTrailing: {
                CompactMarqueeLine(state: context.state)
                    .id(context.state.marqueeIdentity)
            } minimal: {
                ActivityArtwork(data: context.state.artworkData, size: 22)
            }
        }
        // CarPlay (and the Watch Smart Stack) render the .small family;
        // without this opt-in they fall back to the compact Dynamic Island
        // views, which truncate the lyric to one short marquee.
        .supplementalActivityFamilies([.small])
    }
}

struct LockScreenLyricsView: View {
    let context: ActivityViewContext<LyricsAttributes>
    @Environment(\.activityFamily) private var family

    var body: some View {
        Group {
            if family == .small {
                smallBody
                    .animation(
                        .smooth(duration: LiveLyricsAnimationTiming.lineTransitionDuration),
                        value: context.state.marqueeIdentity
                    )
            } else if context.state.usesLineParticles {
                // Do not install a nil animation above the tile transitions.
                mediumBody
            } else {
                mediumBody
                    .animation(
                        .smooth(duration: LiveLyricsAnimationTiming.lineTransitionDuration),
                        value: context.state.marqueeIdentity
                    )
            }
        }
        .activityBackgroundTint(Color.black.opacity(0.75))
        .activitySystemActionForegroundColor(.white)
    }

    /// CarPlay tile / Watch Smart Stack: no room for meta chrome — the
    /// lyric IS the content. Two rows, high contrast.
    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            LiveWordText(state: context.state, minimumScale: 0.7)
                .font(.title3.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(context.state.secondaryLine.isEmpty
                 ? context.state.nextLine
                 : context.state.secondaryLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(context.state.artist.isEmpty
                     ? context.state.title
                     : "\(context.state.title) — \(context.state.artist)")
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)

            LockScreenLineText(state: context.state)
                .font(.title3.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Text(context.state.secondaryLine.isEmpty
                 ? context.state.nextLine
                 : context.state.secondaryLine)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)

        }
        .padding(10)
    }
}

/// The particle canvas has one stable origin and height across lyric changes.
/// No hidden Text is archived underneath its images.
private struct LockScreenLineText: View {
    let state: LyricsAttributes.ContentState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        if state.usesLineParticles && !reduceMotion && !isLuminanceReduced {
            Color.clear
#if canImport(UIKit)
                .frame(height: UIFont.preferredFont(forTextStyle: .title3).lineHeight * 2)
#else
                .frame(height: 48)
#endif
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .topLeading) { LockScreenLineParticles(state: state) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(state.fullLine))
        } else {
            LiveWordText(state: state, minimumScale: 0.75)
        }
    }
}

/// A lyric change removes the old tile views and inserts the new ones. Built-in
/// transitions are archived with those views, so one content update animates
/// both dispersion and gathering without an intermediate blank Activity state.
private struct LockScreenLineParticles: View {
    let state: LyricsAttributes.ContentState
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geometry in
#if canImport(UIKit)
            let base = UIFont.preferredFont(forTextStyle: .title3)
            let font = UIFont(
                descriptor: base.fontDescriptor.withSymbolicTraits(.traitBold)
                    ?? base.fontDescriptor,
                size: base.pointSize
            )
            let raster = LiveLyricsParticleLayout.raster(
                text: state.fullLine,
                size: geometry.size,
                font: font,
                minimumScale: 0.75,
                rightToLeft: layoutDirection == .rightToLeft,
                displayScale: displayScale
            )
            if raster.tiles.isEmpty {
                Text(state.fullLine)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.identity)
            } else {
                ZStack(alignment: .topLeading) {
                    ForEach(raster.tiles) { tile in
                        Image(uiImage: tile.image)
                            .renderingMode(.template)
                            .resizable()
                            .interpolation(.high)
                            .foregroundStyle(.primary)
                            .frame(width: tile.bounds.width, height: tile.bounds.height)
                            .offset(x: tile.bounds.minX, y: tile.bounds.minY)
                            .id(TileIdentity(line: state.particleLineIdentity, tile: tile.id))
                            .transition(particleTransition(tileID: tile.id))
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .animation(.default, value: state.particleLineIdentity)
            }
#else
            Text(state.fullLine)
#endif
        }
        .clipped()
        .environment(\.layoutDirection, .leftToRight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private struct TileIdentity: Hashable {
        let line: LiveLyricsParticleLineIdentity
        let tile: Int
    }

    private func particleTransition(tileID: Int) -> AnyTransition {
        let angle = Double((tileID * 37 + max(0, state.lineIndex ?? 0) % 360 * 13) % 360)
            * .pi / 180
        let distance = CGFloat(18 + tileID % 17)
        let scattered = AnyTransition.offset(
            x: CGFloat(cos(angle)) * distance,
            y: CGFloat(sin(angle)) * distance * 0.5
        )
        .combined(with: .scale(scale: 0.35))
        .combined(with: .opacity)
        // Each side carries its own native animation. The old glyphs finish
        // dispersing before any incoming glyph begins to gather.
        return .asymmetric(
            insertion: scattered.animation(
                .spring(duration: LiveLyricsAnimationTiming.particleGatherDuration, bounce: 0.12)
                    .delay(LiveLyricsAnimationTiming.particleGatherDelay
                        + Double(tileID % 6) * LiveLyricsAnimationTiming.particleStaggerStep)
            ),
            removal: scattered.animation(
                .easeOut(duration: LiveLyricsAnimationTiming.particleDisperseDuration)
            )
        )
    }
}

private struct ActivityArtwork: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
#if canImport(UIKit)
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
#else
            placeholder
#endif
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.25)
            Image(systemName: "music.note")
                .font(.system(size: size * 0.45, weight: .semibold))
        }
    }
}

/// Keep both text layers unchanged throughout a line. Only the built-in offset
/// of the gradient mask animates in the system's archived view representation.
private struct LiveWordText: View {
    let state: LyricsAttributes.ContentState
    let minimumScale: CGFloat
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        Text(state.fullLine)
            .foregroundStyle(baseColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                Text(state.fullLine)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mask { fillMask }
                    .opacity(state.usesWordTiming ? 1 : 0)
                    .accessibilityHidden(true)
            }
    }

    private var baseColor: Color {
        if state.usesWordTiming { return .secondary.opacity(0.55) }
        return state.completedText.isEmpty ? .accentColor : .primary
    }

    private var fillMask: some View {
        GeometryReader { geometry in
#if canImport(UIKit)
            let baseFont = UIFont.preferredFont(forTextStyle: .title3)
            let font = UIFont(
                descriptor: baseFont.fontDescriptor.withSymbolicTraits(.traitBold)
                    ?? baseFont.fontDescriptor,
                size: baseFont.pointSize
            )
            let rows = LiveLyricsFillLayout.rows(
                text: state.fullLine,
                size: geometry.size,
                font: font,
                minimumScale: minimumScale,
                rightToLeft: layoutDirection == .rightToLeft,
                progress: state.fillTarget
            )
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let feather = min(18, max(8, row.bounds.width * 0.04))
                let offset = row.filledWidth > 0
                    ? row.filledWidth - row.bounds.width
                    : -row.bounds.width - feather
                HStack(spacing: 0) {
                    Rectangle().fill(.white)
                        .frame(width: row.bounds.width)
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white.opacity(0.72), location: 0.28),
                            .init(color: .white.opacity(0.25), location: 0.66),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: feather)
                }
                .frame(width: row.bounds.width + feather, height: row.bounds.height)
                .offset(x: offset)
                // Override the fill animation on a line/size change only.
                // Text keeps Apple's default transition; the cursor resets at once.
                .animation(nil, value: state.marqueeIdentity)
                .animation(nil, value: geometry.size)
                .animation(state.wordFillAnimation, value: state.fillTarget)
                .frame(width: row.bounds.width, height: row.bounds.height, alignment: .leading)
                .clipped()
                .environment(\.layoutDirection, .leftToRight)
                .scaleEffect(x: layoutDirection == .rightToLeft ? -1 : 1, y: 1)
                .offset(y: row.bounds.minY)
                .transition(.identity)
            }
#else
            Rectangle()
#endif
        }
    }
}

/// Dynamic Island intentionally stays line-synced. The underlying content
/// still advances for the lock screen, but repartitioning the same words does
/// not create a visible change here until the lyric line itself changes.
private struct LiveLineText: View {
    let state: LyricsAttributes.ContentState

    var body: some View {
        Text(state.completedText + state.activeText + state.remainingText)
    }
}

/// Compact Dynamic Island always performs one line-start-to-tail pass. Word
/// timing remains available to the Lock Screen but doesn't move this view.
private struct CompactMarqueeLine: View {
    let state: LyricsAttributes.ContentState

    private let maximumViewportWidth: CGFloat = 88
    private let minimumViewportWidth: CGFloat = 12
    private let shortLineSafetyPadding: CGFloat = 8
    private let tailRevealPadding: CGFloat = 18

    private var text: String { state.fullLine }

    private var linePassDuration: Double {
        max(0.12, Double(state.lineMarqueeDurationMs) / 1_000)
    }

    private func measuredWidth(_ value: String) -> CGFloat {
#if canImport(UIKit)
        let base = UIFont.preferredFont(forTextStyle: .caption1)
        let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold)
            ?? base.fontDescriptor
        let font = UIFont(descriptor: descriptor, size: base.pointSize)
        return ceil((value as NSString).size(withAttributes: [.font: font]).width)
#else
        return CGFloat(max(value.count, 1)) * 9.5
#endif
    }

    private var measuredTextWidth: CGFloat {
        measuredWidth(text)
    }

    private var safeTextWidth: CGFloat {
        measuredTextWidth + shortLineSafetyPadding
    }

    /// Avoid making the system widen both sides of the compact island for a
    /// lyric that only needs a fraction of the available trailing region.
    /// Keep extra room for glyph overhang and the island's outer clipping.
    private var viewportWidth: CGFloat {
        return min(maximumViewportWidth, max(minimumViewportWidth, safeTextWidth))
    }

    private var travel: CGFloat {
        guard safeTextWidth > viewportWidth else { return 0 }
        let glyphOverflow = max(0, measuredTextWidth - viewportWidth)
        return glyphOverflow + tailRevealPadding
    }

    private var targetOffset: CGFloat {
        return state.lineMarqueeAtEnd ? -travel : 0
    }

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: targetOffset)
            .frame(width: viewportWidth, height: 22, alignment: .leading)
            .clipped()
            .animation(
                .linear(duration: linePassDuration),
                value: state.lineMarqueeAtEnd
            )
    }
}

private extension LyricsAttributes.ContentState {
    var wordFillAnimation: Animation? {
        guard isPlaying, usesWordTiming, fillAnimationDurationMs > 0 else { return nil }
        return .linear(duration: min(2, Double(fillAnimationDurationMs) / 1_000))
    }

    var fullLine: String {
        completedText + activeText + remainingText
    }

    var marqueeIdentity: String {
        "\(title)|\(lineIndex ?? -1)|\(fullLine)"
    }

}

private struct LivePlaybackControls: View {
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: PreviousTrackIntent()) {
                Image(systemName: "backward.end.fill")
                    .frame(width: 42, height: 38)
            }
            Button(intent: SeekPlaybackIntent(offsetSeconds: -15)) {
                Image(systemName: "gobackward.15")
                    .frame(width: 42, height: 38)
            }
            Button(intent: TogglePlaybackIntent()) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 46, height: 38)
            }
            Button(intent: SeekPlaybackIntent(offsetSeconds: 15)) {
                Image(systemName: "goforward.15")
                    .frame(width: 42, height: 38)
            }
            Button(intent: NextTrackIntent()) {
                Image(systemName: "forward.end.fill")
                    .frame(width: 42, height: 38)
            }
        }
        .font(.title3.bold())
        .buttonStyle(.plain)
        .tint(.white)
    }
}

#if DEBUG
// Use WidgetKit's content-state preview, which exercises archived updates,
// including repeated lyrics at different indices and one/two-row changes.
#Preview("Particle lyric transitions", as: .content, using: LyricsAttributes()) {
    LyricsLiveActivity()
} contentStates: {
    particlePreviewState("风吹过，留下清晰的文字", index: 0)
    particlePreviewState("旧句拨散之后，新的歌词从细小粒子重新聚合", index: 1)
    particlePreviewState("旧句拨散之后，新的歌词从细小粒子重新聚合", index: 2)
    particlePreviewState("风吹过，留下清晰的文字", index: 3)
}

private func particlePreviewState(_ line: String, index: Int) -> LyricsAttributes.ContentState {
    LyricsAttributes.ContentState(
        title: "MELS", artist: "DriveVerse", artworkData: nil,
        secondaryLine: "", nextLine: "",
        completedText: line, activeText: "", remainingText: "",
        lyricPositionMs: index * 3_000, positionDate: Date(timeIntervalSince1970: 0),
        activeWordStartMs: 0, activeWordEndMs: 0,
        fillTarget: 0, fillAnimationDurationMs: 0,
        lineIndex: index, usesWordTiming: false, lineMarqueeAtEnd: false,
        lineMarqueeDurationMs: 0, isPlaying: true, lineEffect: .particles
    )
}
#endif
#endif
