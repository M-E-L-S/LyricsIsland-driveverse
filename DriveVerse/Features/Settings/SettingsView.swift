import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var cacheCleared = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable lyrics", isOn: $model.lyricsEnabled)

                Picker("Display", selection: $model.lyricsDisplayMode) {
                    ForEach(LyricsDisplayMode.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .disabled(!model.lyricsEnabled)

                Picker("Chinese characters", selection: $model.chineseConversion) {
                    ForEach(ChineseConversion.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .disabled(!model.lyricsEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Timing offset")
                        Spacer()
                        Text(verbatim: String(
                            format: "%+.1f s",
                            Double(model.lyricsTimingOffsetMs) / 1_000
                        ))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { Double(model.lyricsTimingOffsetMs) },
                            set: { model.lyricsTimingOffsetMs = Int($0.rounded()) }
                        ),
                        in: -5_000...5_000,
                        step: 100
                    )
                    Button("Reset timing offset") {
                        model.resetLyricsTimingOffset()
                    }
                    .disabled(model.lyricsTimingOffsetMs == 0)
                }
                .disabled(!model.lyricsEnabled)
            } header: {
                Text("Lyrics display")
            } footer: {
                Text("Positive values delay the lyrics; negative values show them earlier.")
            }

            Section {
                if let source = model.currentLyricsSource, model.lyricsEnabled {
                    LabeledContent("Current lyrics source", value: String(localized: source.title))
                }
                Button("Rematch lyrics") {
                    model.retryLyrics()
                }
                .disabled(model.nowPlaying == nil || !model.lyricsEnabled)

                Button("Clear lyrics cache") {
                    model.clearLyricsCache()
                    cacheCleared = true
                }
                if cacheCleared {
                    Label("Cache cleared", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } header: {
                Text("Lyrics")
            } footer: {
                Text("Lyrics are searched from Kugou Music, NetEase Cloud Music, then LRCLIB, and cached on this device for at most 30 days.")
            }

            if model.lyricsEnabled, model.nowPlaying != nil {
                Section {
                    if model.lyricsCandidates.isEmpty {
                        Text("Tap Rematch lyrics to load candidates for a result cached by an older version.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if model.isUsingManualLyrics {
                        Button {
                            model.useAutomaticLyrics()
                        } label: {
                            Label("Use automatic match", systemImage: "wand.and.stars")
                        }
                    }

                    ForEach(model.lyricsCandidates) { choice in
                        Button {
                            model.selectLyricsCandidate(choice)
                        } label: {
                            LyricsCandidateRow(
                                choice: choice,
                                isSelected: model.selectedLyricsCandidateID == choice.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Searched lyric candidates")
                } footer: {
                    Text("Only candidates actually reached by lazy search are listed. A manual choice is remembered for this song and lyric display setting.")
                }
            }

            Section {
                Text("Drive Mode keeps DriveVerse awake in the background using a low-power location session, so lyrics keep updating on CarPlay and the lock screen while you drive. Locations are discarded immediately and never stored. It uses extra battery, so it's opt-in. This approach is fine for a personal sideloaded app but would not pass App Store review.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Drive Mode & battery")
            }

            Section {
                Text("DriveVerse is a personal-use app. Lyrics are fetched from third-party services for private, non-commercial display. Do not distribute this app without licensed lyrics providers.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Settings")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

private struct LyricsCandidateRow: View {
    let choice: LyricsCandidateChoice
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(String(localized: choice.source.title))
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                    if choice.evaluation.isWordSynced {
                        Text("Word synced")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if choice.evaluation.secondaryMatches {
                        Text("Secondary text")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(choice.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let preview {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }

    private var details: String {
        var values = [choice.artists.joined(separator: ", ")]
        if let album = choice.album, !album.isEmpty { values.append(album) }
        if let duration = choice.durationMs {
            values.append(String(format: "%d:%02d", duration / 60_000, (duration / 1_000) % 60))
        }
        return values.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var preview: String? {
        guard case .document(let document) = choice.content else { return nil }
        return document.lines.first(where: { !$0.original.isEmpty })?.original
    }
}
