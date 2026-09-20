import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// An immersive, Apple Music-inspired lyrics player. The phone layout keeps
/// lyrics dominant while iPad landscape uses a native two-column composition.
struct LyricsScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsDisplayControls = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LyricsBackdrop(artworkData: model.nowPlaying?.displayArtworkData
                    ?? model.nowPlaying?.artworkData, size: geometry.size)

                if usesTwoColumnLayout(in: geometry.size) {
                    wideLayout(size: geometry.size)
                } else {
                    compactLayout(size: geometry.size)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsDisplayControls) {
            displayControlsSheet
        }
    }

    @ViewBuilder
    private var displayControlsSheet: some View {
#if os(iOS)
        LyricsDisplayControls()
            .environmentObject(model)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
#else
        // The macOS branch exists only for the SwiftPM test harness.
        LyricsDisplayControls()
            .environmentObject(model)
            .frame(minWidth: 480, minHeight: 520)
#endif
    }

    private func usesTwoColumnLayout(in size: CGSize) -> Bool {
        size.width > size.height && size.width >= 900
    }

    private func compactLayout(size: CGSize) -> some View {
        VStack(spacing: 0) {
            compactHeader
            lyricsContent(viewportHeight: max(320, size.height - 260))
                .frame(maxWidth: 760, maxHeight: .infinity)
            if model.nowPlaying != nil {
                CompactNowPlayingControls()
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func wideLayout(size: CGSize) -> some View {
        VStack(spacing: 0) {
            wideHeader
            HStack(spacing: 0) {
                AlbumPlayerPane(availableSize: size)
                    .frame(width: min(440, size.width * 0.40))
                    .padding(.horizontal, 36)

                Rectangle()
                    .fill(.white.opacity(0.10))
                    .frame(width: 1)
                    .padding(.vertical, 28)

                lyricsContent(viewportHeight: size.height - 90)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func lyricsContent(viewportHeight: CGFloat) -> some View {
        if !model.lyricsEnabled {
            placeholder(symbol: "text.badge.xmark", title: "Lyrics are disabled",
                        detail: "Turn lyrics on in Settings to search and display them.")
        } else {
            switch model.lyricsState {
            case .idle:
                placeholder(symbol: "music.note", title: "Nothing playing",
                            detail: "Start a song in Apple Music.")
            case .loading:
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Finding lyrics…")
                        .foregroundStyle(.white.opacity(0.70))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .synced(let document):
                SyncedLyricsView(
                    lines: document.lines,
                    currentIndex: model.position?.lineIndex,
                    playback: model.playbackAnchor ?? model.nowPlaying,
                    timingOffsetMs: model.lyricsTimingOffsetMs,
                    options: model.lyricsDisplayOptions,
                    fontScale: model.lyricsFontScale,
                    lineSpacing: model.lyricsLineSpacing,
                    viewportHeight: viewportHeight,
                    onSeek: seek(to:)
                )
            case .plain(let document):
                PlainLyricsView(
                    document: document,
                    options: model.lyricsDisplayOptions,
                    fontScale: model.lyricsFontScale,
                    lineSpacing: model.lyricsLineSpacing
                )
            case .instrumental:
                placeholder(symbol: "pianokeys", title: "Instrumental",
                            detail: "Sit back and enjoy.")
            case .notFound:
                placeholder(symbol: "text.magnifyingglass", title: "No lyrics found",
                            detail: "No lyrics source has a match for this track.")
            case .failed:
                VStack(spacing: 18) {
                    placeholder(symbol: "wifi.exclamationmark", title: "Couldn't load lyrics",
                                detail: "Check your connection.")
                    Button("Try Again") { model.retryLyrics() }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(.black)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var compactHeader: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(.white.opacity(0.34))
                .frame(width: 54, height: 5)
                .contentShape(Rectangle().inset(by: -12))
                .onTapGesture { dismiss() }

            HStack(spacing: 14) {
                if let state = model.nowPlaying {
                    AlbumArtworkView(
                        data: state.displayArtworkData ?? state.artworkData,
                        size: 68
                    )
                    .shadow(color: .black.opacity(0.24), radius: 14, y: 7)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(state.title)
                            .font(.title3.bold())
                            .lineLimit(1)
                        Text(state.artist)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                } else {
                    Text("Lyrics")
                        .font(.title3.bold())
                }

                Spacer(minLength: 12)

                Button { showsDisplayControls = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3.weight(.bold))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .accessibilityLabel("Lyrics display settings")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 32)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(dismissGesture)
        .accessibilityAction(named: Text("Close lyrics")) { dismiss() }
    }

    private var wideHeader: some View {
        ZStack {
            Capsule()
                .fill(.white.opacity(0.30))
                .frame(width: 54, height: 5)

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.headline.weight(.bold))
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("Close lyrics")

                Spacer()

                Button { showsDisplayControls = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline.weight(.bold))
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("Lyrics display settings")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(dismissGesture)
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let isMostlyVertical = abs(value.translation.height) > abs(value.translation.width)
                if isMostlyVertical && value.translation.height > 80 { dismiss() }
            }
    }

    private func seek(to timeMs: Int) {
        guard let duration = model.nowPlaying?.durationMs, duration > 0 else { return }
        model.seek(toFraction: Double(timeMs) / Double(duration))
    }

    private func placeholder(
        symbol: String,
        title: LocalizedStringResource,
        detail: LocalizedStringResource
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
            Text(title)
                .font(.title3.bold())
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}

// MARK: - Synchronized lyrics

struct SyncedLyricsView: View {
    let lines: [LyricsLine]
    let currentIndex: Int?
    let playback: NowPlayingState?
    let timingOffsetMs: Int
    let options: LyricsDisplayOptions
    let fontScale: Double
    let lineSpacing: Double
    let viewportHeight: CGFloat
    let onSeek: (Int) -> Void

    @ScaledMetric(relativeTo: .title) private var baseLyricSize: CGFloat = 32
    @State private var followsPlayback = true
    @State private var resumeFollowingTask: Task<Void, Never>?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: lineSpacing) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Button {
                            followsPlayback = true
                            resumeFollowingTask?.cancel()
                            onSeek(line.startTimeMs)
                            withAnimation(.snappy(duration: 0.35)) {
                                proxy.scrollTo(index, anchor: lyricFocusAnchor)
                            }
                        } label: {
                            lyricLine(line, at: index)
                        }
                        .buttonStyle(.plain)
                        .id(index)
                        .accessibilityValue(index == currentIndex ? Text("Current lyric") : Text(""))
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, max(52, viewportHeight * 0.18))
                .padding(.bottom, max(180, viewportHeight * 0.76))
            }
            .scrollIndicators(followsPlayback ? .hidden : .visible)
            .onAppear {
                guard let currentIndex else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(currentIndex, anchor: lyricFocusAnchor)
                }
            }
            .onChange(of: currentIndex) { _, newIndex in
                guard followsPlayback, let newIndex else { return }
                withAnimation(.snappy(duration: 0.42)) {
                    proxy.scrollTo(newIndex, anchor: lyricFocusAnchor)
                }
            }
            .onScrollPhaseChange { _, phase in
                switch phase {
                case .tracking, .interacting:
                    followsPlayback = false
                    resumeFollowingTask?.cancel()
                case .idle:
                    scheduleResume(using: proxy)
                default:
                    break
                }
            }
            .onDisappear { resumeFollowingTask?.cancel() }
            .overlay(alignment: .topTrailing) {
                if !followsPlayback {
                    Button {
                        resumeFollowingTask?.cancel()
                        followsPlayback = true
                        if let currentIndex {
                            withAnimation(.snappy(duration: 0.4)) {
                                proxy.scrollTo(currentIndex, anchor: lyricFocusAnchor)
                            }
                        }
                    } label: {
                        Label("Resume", systemImage: "arrow.down.to.line")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                    .transition(.opacity.combined(with: .scale))
                }
            }
        }
    }

    private func lyricLine(_ line: LyricsLine, at index: Int) -> some View {
        let isCurrent = index == currentIndex
        return VStack(alignment: .leading, spacing: 7) {
            Group {
                if isCurrent, line.words?.isEmpty == false, let playback {
                    WordTimedText(
                        line: line,
                        playback: playback,
                        timingOffsetMs: timingOffsetMs,
                        options: options,
                        completedColor: .white,
                        activeColor: .white,
                        pendingColor: .white.opacity(0.34)
                    )
                } else {
                    Text(LyricsTextRenderer.primary(for: line, options: options))
                }
            }
            .font(.system(size: baseLyricSize * fontScale, weight: .bold))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)

            if let secondary = LyricsTextRenderer.secondary(for: line, options: options) {
                Text(secondary)
                    .font(.system(size: baseLyricSize * fontScale * 0.58, weight: isCurrent ? .semibold : .medium))
                    .lineSpacing(2)
                    .foregroundStyle(.white.opacity(isCurrent ? 0.70 : 0.38))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .opacity(opacity(for: index))
        .blur(radius: blurRadius(for: index))
        .scaleEffect(isCurrent ? 1 : 0.985, anchor: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.28), value: currentIndex)
    }

    private func opacity(for index: Int) -> Double {
        guard let currentIndex else { return 0.40 }
        if index == currentIndex { return 1 }
        if !followsPlayback { return 0.34 }
        return abs(index - currentIndex) == 1 ? 0.25 : 0.14
    }

    private func blurRadius(for index: Int) -> CGFloat {
        guard followsPlayback, let currentIndex, index != currentIndex else { return 0 }
        return abs(index - currentIndex) == 1 ? 1.2 : 2.4
    }

    private var lyricFocusAnchor: UnitPoint {
        UnitPoint(x: 0.5, y: 0.24)
    }

    private func scheduleResume(using proxy: ScrollViewProxy) {
        guard !followsPlayback else { return }
        resumeFollowingTask?.cancel()
        resumeFollowingTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            followsPlayback = true
            if let currentIndex {
                withAnimation(.snappy(duration: 0.45)) {
                    proxy.scrollTo(currentIndex, anchor: lyricFocusAnchor)
                }
            }
        }
    }
}

// MARK: - Plain lyrics

private struct PlainLyricsView: View {
    let document: LyricsDocument
    let options: LyricsDisplayOptions
    let fontScale: Double
    let lineSpacing: Double
    @ScaledMetric(relativeTo: .title2) private var baseSize: CGFloat = 24

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: lineSpacing) {
                Label("Lyrics aren't time-synced for this track", systemImage: "clock.badge.questionmark")
                    .font(.footnote.bold())
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.bottom, 8)

                ForEach(Array(document.lines.enumerated()), id: \.offset) { _, line in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(LyricsTextRenderer.primary(for: line, options: options))
                            .font(.system(size: baseSize * fontScale, weight: .semibold))
                            .lineSpacing(lineSpacing * 0.35)
                            .fixedSize(horizontal: false, vertical: true)
                        if let secondary = LyricsTextRenderer.secondary(for: line, options: options) {
                            Text(secondary)
                                .font(.system(size: baseSize * fontScale * 0.62, weight: .medium))
                                .foregroundStyle(.white.opacity(0.52))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .foregroundStyle(.white.opacity(0.88))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 48)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Player chrome

private struct CompactNowPlayingControls: View {
    var body: some View {
        PlaybackControlsView(style: .immersive)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }
}

private struct AlbumPlayerPane: View {
    @EnvironmentObject private var model: AppModel
    let availableSize: CGSize

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)
            if let state = model.nowPlaying {
                AlbumArtworkView(
                    data: state.displayArtworkData ?? state.artworkData,
                    size: min(340, availableSize.height * 0.39)
                )
                .shadow(color: .black.opacity(0.42), radius: 30, y: 16)

                VStack(spacing: 5) {
                    Text(state.title)
                        .font(.title3.bold())
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(state.artist)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                .frame(maxWidth: 360)

                PlaybackControlsView(style: .immersive)
                    .frame(maxWidth: 360)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 12)
        }
        .foregroundStyle(.white)
    }
}

private struct LyricsBackdrop: View {
    let artworkData: Data?
    let size: CGSize

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.30, green: 0.12, blue: 0.20), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
#if canImport(UIKit)
            if let image = ArtworkImageCache.image(from: artworkData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .saturation(1.55)
                    .contrast(1.12)
                    .blur(radius: 58)
                    .scaleEffect(1.34)
                    .opacity(0.94)
            }
#endif
            Color.black.opacity(0.20)
            RadialGradient(
                colors: [.white.opacity(0.12), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 520
            )
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.08), location: 0.48),
                    .init(color: .black.opacity(0.66), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Display controls

private struct LyricsDisplayControls: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Lyrics") {
                    Picker("Display", selection: $model.lyricsDisplayMode) {
                        ForEach(LyricsDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }

                Section("Text") {
                    sliderRow(
                        title: "Text size",
                        value: $model.lyricsFontScale,
                        range: 0.80...1.35,
                        step: 0.05,
                        valueText: "\(Int((model.lyricsFontScale * 100).rounded()))%"
                    )
                    sliderRow(
                        title: "Line spacing",
                        value: $model.lyricsLineSpacing,
                        range: 10...34,
                        step: 2,
                        valueText: "\(Int(model.lyricsLineSpacing.rounded()))"
                    )
                }

                Section {
                    sliderRow(
                        title: "Timing offset",
                        value: Binding(
                            get: { Double(model.lyricsTimingOffsetMs) },
                            set: { model.lyricsTimingOffsetMs = Int($0.rounded()) }
                        ),
                        range: -5_000...5_000,
                        step: 100,
                        valueText: String(format: "%+.1f s", Double(model.lyricsTimingOffsetMs) / 1_000)
                    )
                    Button("Reset timing offset") { model.resetLyricsTimingOffset() }
                        .disabled(model.lyricsTimingOffsetMs == 0)
                } footer: {
                    Text("Positive values delay the lyrics; negative values show them earlier.")
                }
            }
            .navigationTitle("Lyrics display")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func sliderRow(
        title: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
        }
    }
}
