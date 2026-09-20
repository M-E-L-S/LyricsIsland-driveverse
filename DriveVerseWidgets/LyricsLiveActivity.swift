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
                CompactMarqueeLine(text: context.state.fullLine)
                    .id(context.state.fullLine)
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

/// Compact Dynamic Island gets only a narrow fixed region. Scroll a stable
/// full-line string locally so word-level ContentState updates do not restart
/// the animation. This is deliberately independent of ActivityKit cadence.
private struct CompactMarqueeLine: View {
    let text: String

    @State private var showingEnd = false

    private let viewportWidth: CGFloat = 88
    private let pointsPerSecond: CGFloat = 14

    private var estimatedTextWidth: CGFloat {
#if canImport(UIKit)
        let base = UIFont.preferredFont(forTextStyle: .caption1)
        let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold)
            ?? base.fontDescriptor
        let font = UIFont(descriptor: descriptor, size: base.pointSize)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
#else
        return CGFloat(max(text.count, 1)) * 9.5
#endif
    }

    private var travel: CGFloat {
        max(0, estimatedTextWidth - viewportWidth)
    }

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: showingEnd ? -travel : 0)
            .frame(width: viewportWidth, height: 22, alignment: .leading)
            .clipped()
            .onAppear {
                guard travel > 0 else { return }
                withAnimation(
                    .linear(duration: max(2.5, Double(travel / pointsPerSecond)))
                    .repeatForever(autoreverses: true)
                ) {
                    showingEnd = true
                }
            }
    }
}

private extension LyricsAttributes.ContentState {
    var fullLine: String {
        completedText + activeText + remainingText
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
