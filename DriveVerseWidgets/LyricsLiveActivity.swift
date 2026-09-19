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
            // one small meta row, two text rows, a progress bar.
            LockScreenLyricsView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityArtwork(data: context.state.artworkData, size: 42)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        LiveWordText(state: context.state)
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Text(context.state.secondaryLine.isEmpty
                             ? context.state.nextLine
                             : context.state.secondaryLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 7) {
                        LiveTrackProgress(state: context.state)
                        LivePlaybackControls(isPlaying: context.state.isPlaying)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                ActivityArtwork(data: context.state.artworkData, size: 22)
            } compactTrailing: {
                MarqueeLyricText(
                    text: context.state.currentLine,
                    anchor: context.state.playbackReferenceDate
                )
                .font(.caption2)
                .frame(maxWidth: 72)
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
            } else {
                mediumBody
            }
        }
        .activityBackgroundTint(Color.black.opacity(0.75))
        .activitySystemActionForegroundColor(.white)
    }

    /// CarPlay tile / Watch Smart Stack: no room for meta chrome — the
    /// lyric IS the content. Two rows, high contrast; controls remain in the
    /// regular lock-screen and expanded Dynamic Island presentations.
    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            LiveWordText(state: context.state)
                .font(.title3.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .contentTransition(.opacity)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(context.state.secondaryLine.isEmpty
                 ? context.state.nextLine
                 : context.state.secondaryLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .id(context.state.secondaryLine.isEmpty
                    ? context.state.nextLine
                    : context.state.secondaryLine)
                .transition(.push(from: .bottom))
        }
        .padding(10)
        .animation(.smooth(duration: 0.5), value: context.state)
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

            LiveWordText(state: context.state)
                .font(.title3.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Text(context.state.secondaryLine.isEmpty
                 ? context.state.nextLine
                 : context.state.secondaryLine)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            LiveTrackProgress(state: context.state)
            LivePlaybackControls(isPlaying: context.state.isPlaying)
        }
        .padding(10)
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

/// Word highlighting is rendered from the playback anchor carried in the last
/// Activity update. It animates locally and does not spend ActivityKit updates.
private struct LiveWordText: View {
    let state: LyricsAttributes.ContentState

    @ViewBuilder
    var body: some View {
        if state.isPlaying, !state.currentWords.isEmpty {
            TimelineView(.periodic(from: state.playbackReferenceDate, by: 0.08)) { timeline in
                Text(text(at: timeline.date))
            }
        } else {
            Text(text(at: state.playbackReferenceDate))
        }
    }

    private func text(at date: Date) -> AttributedString {
        guard !state.currentWords.isEmpty else { return AttributedString(state.currentLine) }
        let position = state.lyricPositionMs + elapsedMs(at: date)
        var result = AttributedString()
        for word in state.currentWords {
            var part = AttributedString(word.text)
            if position >= word.endTimeMs {
                part.foregroundColor = .primary
            } else if position >= word.startTimeMs {
                part.foregroundColor = .accentColor
            } else {
                part.foregroundColor = .secondary.opacity(0.5)
            }
            result.append(part)
        }
        return result
    }

    private func elapsedMs(at date: Date) -> Int {
        guard state.isPlaying else { return 0 }
        return max(0, Int(date.timeIntervalSince(state.playbackReferenceDate) * 1_000))
    }
}

/// Compact Dynamic Island has no horizontal scroll container, so move a
/// single fixed-size line through its clipped viewport with short end pauses.
private struct MarqueeLyricText: View {
    let text: String
    let anchor: Date

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.periodic(from: anchor, by: 0.08)) { timeline in
                Text(text)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: offset(at: timeline.date, viewport: geometry.size.width))
            }
        }
        .clipped()
    }

    private func offset(at date: Date, viewport: CGFloat) -> CGFloat {
        let estimatedWidth = CGFloat(text.count) * 8.5
        let travel = max(0, estimatedWidth - viewport)
        guard travel > 0 else { return 0 }
        let duration = max(6.0, min(16.0, Double(text.count) * 0.28))
        let elapsed = max(0, date.timeIntervalSince(anchor))
        let phase = elapsed.truncatingRemainder(dividingBy: duration) / duration
        if phase < 0.15 { return 0 }
        if phase > 0.85 { return -travel }
        return -travel * CGFloat((phase - 0.15) / 0.70)
    }
}

private struct LiveTrackProgress: View {
    let state: LyricsAttributes.ContentState

    var body: some View {
        TimelineView(.periodic(from: state.playbackReferenceDate, by: 0.25)) { timeline in
            ProgressView(value: progress(at: timeline.date))
                .tint(.white.opacity(0.85))
        }
    }

    private func progress(at date: Date) -> Double {
        guard let duration = state.durationMs, duration > 0 else { return state.progress }
        let elapsed = state.isPlaying
            ? max(0, Int(date.timeIntervalSince(state.playbackReferenceDate) * 1_000))
            : 0
        return min(1, max(0, Double(state.trackPositionMs + elapsed) / Double(duration)))
    }
}

private struct LivePlaybackControls: View {
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button(intent: PreviousTrackIntent()) {
                Image(systemName: "backward.end.fill")
                    .frame(width: 32, height: 28)
            }
            Button(intent: SeekPlaybackIntent(offsetSeconds: -15)) {
                Image(systemName: "gobackward.15")
                    .frame(width: 32, height: 28)
            }
            Button(intent: TogglePlaybackIntent()) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 36, height: 28)
            }
            Button(intent: SeekPlaybackIntent(offsetSeconds: 15)) {
                Image(systemName: "goforward.15")
                    .frame(width: 32, height: 28)
            }
            Button(intent: NextTrackIntent()) {
                Image(systemName: "forward.end.fill")
                    .frame(width: 32, height: 28)
            }
        }
        .font(.caption.bold())
        .buttonStyle(.plain)
        .tint(.white)
    }
}
#endif
