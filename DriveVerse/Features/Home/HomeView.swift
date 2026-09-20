import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsLyrics = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    NowPlayingCard()
                    LyricPreviewCard { showsLyrics = true }
                    DriveModeCard()
                    if model.appleMusicAuth == .denied {
                        InfoBanner(
                            symbol: "exclamationmark.triangle",
                            text: String(localized: "Apple Music detection is off. Allow Media & Apple Music access in Settings → DriveVerse.")
                        )
                    }
                    if let message = model.errorMessage {
                        InfoBanner(symbol: "xmark.octagon", text: message)
                    }
                }
                .padding()
            }
            .navigationTitle("DriveVerse")
            .toolbar {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .task { model.start() }
#if os(iOS)
        .fullScreenCover(isPresented: $showsLyrics) {
            LyricsScreen()
                .environmentObject(model)
        }
#else
        // SwiftPM compiles the shared source target for macOS in CI, where
        // fullScreenCover is explicitly unavailable. The shipping app takes
        // the iOS branch above; this sheet only keeps the core test harness
        // buildable.
        .sheet(isPresented: $showsLyrics) {
            LyricsScreen()
                .environmentObject(model)
        }
#endif
    }
}

// MARK: - Now playing

private struct NowPlayingCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let state = model.nowPlaying {
                HStack(spacing: 12) {
                    AlbumArtworkView(data: state.displayArtworkData ?? state.artworkData)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(state.title)
                            .font(.title2.bold())
                            .lineLimit(2)
                        Text(state.artist)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                PlaybackControlsView()
                    .padding(.top, 4)
            } else {
                Label("Nothing playing", systemImage: "music.note")
                    .foregroundStyle(.secondary)
                Text("Start a song in Apple Music — DriveVerse picks it up automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Lyrics preview → full screen

private struct LyricPreviewCard: View {
    @EnvironmentObject private var model: AppModel
    let openLyrics: () -> Void

    var body: some View {
        Button(action: openLyrics) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Lyrics", systemImage: "quote.opening")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !model.lyricsEnabled {
                    Text("Lyrics are disabled").foregroundStyle(.secondary)
                } else {
                    switch model.lyricsState {
                    case .idle:
                        Text("Lyrics show up here").foregroundStyle(.secondary)
                    case .loading:
                        Text("Finding lyrics…").foregroundStyle(.secondary)
                    case .synced:
                        Text(model.position?.currentLine ?? "♪")
                            .font(.headline)
                            .lineLimit(2)
                        if let secondary = model.position?.currentSecondaryLine {
                            Text(secondary)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        } else if let next = model.position?.nextLine {
                            Text(next)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    case .plain:
                        Text("Lyrics available (not synced)").font(.headline)
                    case .instrumental:
                        Text("Instrumental 🎶").foregroundStyle(.secondary)
                    case .notFound:
                        Text("No lyrics found").foregroundStyle(.secondary)
                    case .failed:
                        Text("Couldn't load lyrics").foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the full-screen lyrics player")
    }
}

// MARK: - Drive Mode

private struct DriveModeCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $model.driveMode) {
                Label("Drive Mode", systemImage: "car.fill")
                    .font(.headline)
            }
            Text("Keeps lyrics updating in the background for CarPlay. Uses a little more battery — turn it on only while driving.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Shared bits

struct InfoBanner: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }
}
