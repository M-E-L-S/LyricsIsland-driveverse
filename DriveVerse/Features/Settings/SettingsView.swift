import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var cacheCleared = false

    var body: some View {
        Form {
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
