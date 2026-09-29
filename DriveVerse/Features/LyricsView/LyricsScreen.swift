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
            Group {
                if usesTwoColumnLayout(in: geometry.size) {
                    wideLayout(size: geometry.size)
                } else {
                    compactLayout(size: geometry.size)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background {
                // Keep the animated mesh out of foreground layout while it
                // paints under the safe areas.
                LyricsBackdrop(artworkData: model.nowPlaying?.displayArtworkData
                    ?? model.nowPlaying?.artworkData,
                    isPlaying: model.nowPlaying?.isPlaying == true)
            }
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
                    lyricPositionMs: model.position?.lyricPositionMs,
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
    let lyricPositionMs: Int?
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
                        Group {
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

                            if let gap = breathingGap(after: index) {
                                BreathingDots(
                                    startTimeMs: gap.startTimeMs,
                                    endTimeMs: gap.endTimeMs,
                                    reportedPositionMs: lyricPositionMs,
                                    playback: playback,
                                    timingOffsetMs: timingOffsetMs
                                )
                                .id(BreathingRowID(lineIndex: index))
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, max(52, viewportHeight * 0.18))
                .padding(.bottom, max(180, viewportHeight * 0.76))
            }
            .scrollIndicators(followsPlayback ? .hidden : .visible)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.42), location: 0.055),
                        .init(color: .white, location: 0.13),
                        .init(color: .white, location: 0.80),
                        .init(color: .white.opacity(0.46), location: 0.91),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .onAppear {
                guard let currentIndex else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(currentIndex, anchor: lyricFocusAnchor)
                }
            }
            .onChange(of: currentIndex) { _, newIndex in
                guard followsPlayback, let newIndex else { return }
                withAnimation(.timingCurve(0.22, 0.68, 0.24, 1, duration: 1.55)) {
                    proxy.scrollTo(newIndex, anchor: lyricFocusAnchor)
                }
            }
            .onChange(of: activeBreatherIndex) { _, lineIndex in
                guard followsPlayback, let lineIndex else { return }
                withAnimation(.timingCurve(0.22, 0.68, 0.24, 1, duration: 1.10)) {
                    proxy.scrollTo(BreathingRowID(lineIndex: lineIndex), anchor: lyricFocusAnchor)
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
        let isCurrent = index == currentIndex && activeBreatherIndex == nil
        return VStack(alignment: .leading, spacing: 7) {
            Group {
                if index == currentIndex, line.words?.isEmpty == false, let playback {
                    WordTimedText(
                        line: line,
                        playback: playback,
                        timingOffsetMs: timingOffsetMs,
                        options: options,
                        completedColor: .white,
                        activeColor: .white,
                        pendingColor: .white.opacity(0.34)
                    )
                    .transition(.identity)
                } else if line.words?.isEmpty == false {
                    StaticWordTimedText(line: line, options: options)
                        .transition(.identity)
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
        .animation(.easeOut(duration: 0.24), value: opacity(for: index))
        .offset(y: layeredLift(for: index))
        .animation(
            .timingCurve(0.22, 0.68, 0.24, 1, duration: 0.90)
                .delay(Double(min(3, abs(index - (currentIndex ?? index)))) * 0.22),
            value: currentIndex
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func opacity(for index: Int) -> Double {
        guard let currentIndex else { return 0.40 }
        if index == currentIndex { return activeBreatherIndex == index ? 0.22 : 1 }
        if !followsPlayback { return 0.34 }
        return abs(index - currentIndex) == 1 ? 0.32 : 0.18
    }

    private func layeredLift(for index: Int) -> CGFloat {
        guard let currentIndex else { return 0 }
        // The active row moves first, then the two rows above it. A lasting
        // upward step avoids any snap-back or overlapping text at the end.
        return -CGFloat(min(3, max(0, currentIndex - index + 1))) * 18
    }

    private var lyricFocusAnchor: UnitPoint {
        UnitPoint(x: 0.5, y: 0.24)
    }

    private var activeBreatherIndex: Int? {
        guard let lyricPositionMs, let currentIndex,
              let gap = breathingGap(after: currentIndex),
              lyricPositionMs >= gap.startTimeMs,
              lyricPositionMs < gap.endTimeMs else { return nil }
        return currentIndex
    }

    private func breathingGap(after index: Int) -> BreathingGap? {
        guard index + 1 < lines.count else { return nil }
        let line = lines[index]
        let nextStart = lines[index + 1].startTimeMs
        let start: Int

        if line.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            start = line.startTimeMs + 350
        } else if let lastWordEnd = line.words?.last?.endTimeMs {
            start = lastWordEnd + 450
        } else {
            let interval = nextStart - line.startTimeMs
            guard interval >= 8_000 else { return nil }
            start = line.startTimeMs + max(4_800, Int(Double(interval) * 0.68))
        }

        guard nextStart - start >= 2_400 else { return nil }
        return BreathingGap(startTimeMs: start, endTimeMs: nextStart)
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

private struct BreathingGap {
    let startTimeMs: Int
    let endTimeMs: Int
}

private struct BreathingRowID: Hashable {
    let lineIndex: Int
}

private struct BreathingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let startTimeMs: Int
    let endTimeMs: Int
    let reportedPositionMs: Int?
    let playback: NowPlayingState?
    let timingOffsetMs: Int

    var body: some View {
        TimelineView(.animation(
            minimumInterval: 1.0 / 20.0,
            paused: reduceMotion || !isActive || playback?.isPlaying != true
        )) { timeline in
            let position = playback.map {
                SyncEngine.extrapolatedPositionMs(anchor: $0, at: timeline.date) - timingOffsetMs
            } ?? reportedPositionMs ?? startTimeMs
            let state = visualState(at: position)

            HStack(spacing: 9) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(.white.opacity(0.25 + 0.75 * illumination(
                            for: index,
                            progress: state.progress
                        )))
                        .frame(width: 10, height: 10)
                }
            }
            .scaleEffect(state.scale)
            .offset(y: state.offsetY)
            .opacity(state.opacity)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .accessibilityHidden(true)
    }

    private var isActive: Bool {
        guard let reportedPositionMs else { return false }
        return reportedPositionMs >= startTimeMs && reportedPositionMs < endTimeMs
    }

    private func visualState(at position: Int) -> (
        opacity: Double, offsetY: CGFloat, scale: CGFloat, progress: Double
    ) {
        let duration = max(1, endTimeMs - startTimeMs)
        let progress = min(1, max(0, Double(position - startTimeMs) / Double(duration)))

        if position < startTimeMs || position >= endTimeMs {
            return (0, 12, 0.86, progress)
        }
        if reduceMotion {
            return (0.88, -2, 1, 1)
        }
        if progress < 0.30 {
            let entrance = smoothStep(progress / 0.30)
            return (entrance, 9 - CGFloat(entrance) * 13, 0.88 + CGFloat(entrance) * 0.12, progress)
        }
        if progress > 0.78 {
            let exit = min(1, max(0, (progress - 0.78) / 0.22))
            let drop = smoothStep(exit)
            return (1 - drop, -4 + CGFloat(drop) * 16, 1 - CGFloat(exit) * 0.10, progress)
        }

        let breath = sin((progress - 0.30) / 0.48 * .pi * 2)
        return (0.90 + breath * 0.08, -4 - CGFloat(breath) * 1.2, 1 + CGFloat(breath) * 0.04, progress)
    }

    private func illumination(for index: Int, progress: Double) -> Double {
        smoothStep(min(1, max(0, (progress - Double(index) * 0.13) / 0.24)))
    }

    private func smoothStep(_ value: Double) -> Double {
        value * value * (3 - 2 * value)
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
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white, location: 0.10),
                    .init(color: .white, location: 0.88),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var animationOrigin = Date()
    let artworkData: Data?
    let isPlaying: Bool

    var body: some View {
        GeometryReader { geometry in
            let palette = meshColors
            TimelineView(.animation(minimumInterval: 1.0 / 10.0,
                                    paused: reduceMotion || scenePhase != .active || !isPlaying)) { timeline in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSince(animationOrigin)
                let lightCenter = UnitPoint(
                    x: 0.50 + CGFloat(sin(time * 0.44)) * 0.34,
                    y: 0.44 + CGFloat(cos(time * 0.39)) * 0.30
                )
                let secondCenter = UnitPoint(
                    x: 0.50 + CGFloat(cos(time * 0.33 + 1.7)) * 0.36,
                    y: 0.50 + CGFloat(sin(time * 0.37 + 0.8)) * 0.35
                )

                ZStack {
                    MeshGradient(
                        width: 4,
                        height: 4,
                        points: meshPoints(at: time),
                        colors: palette,
                        background: palette[5]
                    )
                    .scaleEffect(1.28)
                    .rotationEffect(.degrees(sin(time * 0.28) * 7))
                    RadialGradient(
                        colors: [palette[5].opacity(0.70), .clear],
                        center: lightCenter,
                        startRadius: 0,
                        endRadius: max(240, geometry.size.width * 0.85)
                    )
                    RadialGradient(
                        colors: [palette[10].opacity(0.62), .clear],
                        center: secondCenter,
                        startRadius: 0,
                        endRadius: max(260, geometry.size.width * 0.95)
                    )
                    Color.black.opacity(0.28)
                    RadialGradient(
                        colors: [.white.opacity(0.16), .clear],
                        center: lightCenter,
                        startRadius: 0,
                        endRadius: max(240, geometry.size.width * 0.80)
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
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var meshColors: [Color] {
#if canImport(UIKit)
        ArtworkMeshPalette.colors(from: artworkData)
#else
        Self.fallbackColors
#endif
    }

    private func meshPoints(at time: TimeInterval) -> [SIMD2<Float>] {
        (0..<16).map { index in
            let column = index % 4
            let row = index / 4
            var x = Float(column) / 3
            var y = Float(row) / 3
            if column > 0 && column < 3 {
                x += Float(sin(time * 0.55 + Double(row) * 1.7 + Double(column) * 0.8)) * 0.13
            }
            if row > 0 && row < 3 {
                y += Float(cos(time * 0.50 + Double(column) * 1.5 + Double(row) * 0.9)) * 0.13
            }
            return SIMD2(x, y)
        }
    }

    fileprivate static let fallbackColors: [Color] = [
        Color(red: 0.22, green: 0.09, blue: 0.20), Color(red: 0.33, green: 0.12, blue: 0.23),
        Color(red: 0.15, green: 0.10, blue: 0.28), Color(red: 0.09, green: 0.08, blue: 0.19),
        Color(red: 0.28, green: 0.10, blue: 0.23), Color(red: 0.43, green: 0.15, blue: 0.25),
        Color(red: 0.16, green: 0.13, blue: 0.36), Color(red: 0.11, green: 0.12, blue: 0.29),
        Color(red: 0.25, green: 0.12, blue: 0.28), Color(red: 0.35, green: 0.15, blue: 0.34),
        Color(red: 0.13, green: 0.13, blue: 0.31), Color(red: 0.08, green: 0.09, blue: 0.21),
        Color(red: 0.14, green: 0.08, blue: 0.19), Color(red: 0.24, green: 0.11, blue: 0.25),
        Color(red: 0.10, green: 0.10, blue: 0.22), Color(red: 0.06, green: 0.07, blue: 0.16)
    ]
}

#if canImport(UIKit)
private final class ArtworkMeshColors: NSObject {
    let values: [Color]

    init(_ values: [Color]) {
        self.values = values
    }
}

private enum ArtworkMeshPalette {
    private static let cache: NSCache<NSData, ArtworkMeshColors> = {
        let cache = NSCache<NSData, ArtworkMeshColors>()
        cache.countLimit = 8
        return cache
    }()

    static func colors(from data: Data?) -> [Color] {
        guard let data else { return LyricsBackdrop.fallbackColors }
        let key = data as NSData
        if let cached = cache.object(forKey: key) { return cached.values }
        guard let image = ArtworkImageCache.image(from: data)?.cgImage else {
            return LyricsBackdrop.fallbackColors
        }

        let side = 4
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drew = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drew else { return LyricsBackdrop.fallbackColors }

        let colors = (0..<(side * side)).map { index -> Color in
            let offset = index * 4
            return Color(
                red: min(1, Double(pixels[offset]) / 255 * 1.18 + 0.025),
                green: min(1, Double(pixels[offset + 1]) / 255 * 1.18 + 0.025),
                blue: min(1, Double(pixels[offset + 2]) / 255 * 1.18 + 0.025)
            )
        }
        cache.setObject(ArtworkMeshColors(colors), forKey: key)
        return colors
    }
}
#endif

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
