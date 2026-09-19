import SwiftUI

/// Full-screen lyrics for passengers / parked use.
/// Display-only by design: DriveVerse observes another app's playback and
/// cannot seek, so there is no tap-to-scrub.
struct LyricsScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch model.lyricsState {
            case .idle:
                placeholder(symbol: "music.note", title: "Nothing playing",
                            detail: "Start a song in Apple Music.")
            case .loading:
                ProgressView("Finding lyrics…")
            case .synced(let document):
                SyncedLyricsView(
                    lines: document.lines,
                    currentIndex: model.position?.lineIndex,
                    options: model.lyricsDisplayOptions
                )
            case .plain(let document):
                PlainLyricsView(document: document, options: model.lyricsDisplayOptions)
            case .instrumental:
                placeholder(symbol: "pianokeys", title: "Instrumental",
                            detail: "Sit back and enjoy.")
            case .notFound:
                placeholder(symbol: "text.magnifyingglass", title: "No lyrics found",
                            detail: "No lyrics source has a match for this track.")
            case .failed:
                VStack(spacing: 12) {
                    placeholder(symbol: "wifi.exclamationmark", title: "Couldn't load lyrics",
                                detail: "Check your connection.")
                    Button("Try Again") { model.retryLyrics() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(model.nowPlaying?.title ?? String(localized: "Lyrics"))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    private func placeholder(
        symbol: String,
        title: LocalizedStringResource,
        detail: LocalizedStringResource
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title).font(.title3.bold())
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

struct SyncedLyricsView: View {
    let lines: [LyricsLine]
    let currentIndex: Int?
    let options: LyricsDisplayOptions

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(LyricsTextRenderer.primary(for: line, options: options))
                                .font(index == currentIndex ? .title2.bold() : .title3)
                            if let secondary = LyricsTextRenderer.secondary(for: line, options: options) {
                                Text(secondary)
                                    .font(index == currentIndex ? .body : .callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                            .foregroundStyle(index == currentIndex ? .primary : .secondary)
                            .opacity(index == currentIndex ? 1 : 0.55)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 140) // headroom so the current line can center
            }
            .onChange(of: currentIndex) { _, newIndex in
                guard let newIndex else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }
}

private struct PlainLyricsView: View {
    let document: LyricsDocument
    let options: LyricsDisplayOptions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Lyrics aren't time-synced for this track", systemImage: "clock.badge.questionmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(Array(document.lines.enumerated()), id: \.offset) { _, line in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LyricsTextRenderer.primary(for: line, options: options))
                            .font(.title3)
                        if let secondary = LyricsTextRenderer.secondary(for: line, options: options) {
                            Text(secondary)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }
}
