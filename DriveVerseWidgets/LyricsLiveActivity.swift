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
                                .lineLimit(2)
                                .minimumScaleFactor(0.72)
                            Text(context.state.secondaryLine.isEmpty
                                 ? context.state.nextLine
                                 : context.state.secondaryLine)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
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
                LiveLineText(state: context.state)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 88, height: 22, alignment: .leading)
                    .clipped()
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
    /// lyric IS the content. Two rows, high contrast.
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

/// ActivityKit does not reliably advance TimelineView while the app is in the
/// background. The app therefore sends these tiny segments on word changes.
private struct LiveWordText: View {
    let state: LyricsAttributes.ContentState

    var body: some View {
        Text(state.completedText).foregroundColor(.primary)
        + Text(state.activeText).foregroundColor(.accentColor)
        + Text(state.remainingText).foregroundColor(.secondary.opacity(0.55))
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
#endif
