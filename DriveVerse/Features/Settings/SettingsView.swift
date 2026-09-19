import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var cacheCleared = false

    var body: some View {
        Form {
            Section {
                Picker("Display", selection: $model.lyricsDisplayMode) {
                    ForEach(LyricsDisplayMode.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                Picker("Chinese characters", selection: $model.chineseConversion) {
                    ForEach(ChineseConversion.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

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
            } header: {
                Text("Lyrics display")
            } footer: {
                Text("Positive values delay the lyrics; negative values show them earlier.")
            }

            Section {
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
                Text("Lyrics come from LRCLIB and are cached on this device for at most 30 days.")
            }

            Section {
                Text("Drive Mode keeps DriveVerse awake in the background using a low-power location session, so lyrics keep updating on CarPlay and the lock screen while you drive. Locations are discarded immediately and never stored. It uses extra battery, so it's opt-in. This approach is fine for a personal sideloaded app but would not pass App Store review.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Drive Mode & battery")
            }

            Section {
                Text("DriveVerse is a personal-use app. Lyrics are fetched from the community-run LRCLIB API for private, non-commercial display. Do not distribute this app without a licensed lyrics provider.")
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
