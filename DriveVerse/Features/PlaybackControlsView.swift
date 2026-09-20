import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit

enum ArtworkImageCache {
    private static let cache: NSCache<NSData, UIImage> = {
        let cache = NSCache<NSData, UIImage>()
        cache.countLimit = 8
        return cache
    }()

    static func image(from data: Data?) -> UIImage? {
        guard let data else { return nil }
        let key = data as NSData
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
#endif

struct AlbumArtworkView: View {
    let data: Data?
    var size: CGFloat = 56

    var body: some View {
        Group {
#if canImport(UIKit)
            if let image = ArtworkImageCache.image(from: data) {
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
        .clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
        }
    }
}

struct PlaybackControlsView: View {
    enum Style: Equatable {
        case standard
        case immersive
    }

    @EnvironmentObject private var model: AppModel
    @State private var draggedProgress = 0.0
    @State private var isDragging = false
    var style: Style = .standard

    var body: some View {
        VStack(spacing: 10) {
            if let state = model.nowPlaying, let duration = state.durationMs, duration > 0 {
                Slider(
                    value: Binding(
                        get: { isDragging ? draggedProgress : model.position?.trackProgress ?? 0 },
                        set: { draggedProgress = $0 }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        if editing {
                            draggedProgress = model.position?.trackProgress ?? 0
                            isDragging = true
                        } else {
                            model.seek(toFraction: draggedProgress)
                            isDragging = false
                        }
                    }
                )
                .tint(style == .immersive ? .white : .accentColor)
                .accessibilityLabel("Playback position")

                HStack {
                    Text(timeText(progress: displayedProgress, durationMs: duration))
                    Spacer()
                    Text(timeText(progress: 1, durationMs: duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            HStack(spacing: style == .immersive ? 48 : 34) {
                controlButton("backward.end.fill", label: "Previous Track") {
                    model.skipToPreviousItem()
                }
                controlButton(
                    model.nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill",
                    label: model.nowPlaying?.isPlaying == true ? "Pause" : "Play",
                    prominent: true
                ) {
                    model.togglePlayback()
                }
                controlButton("forward.end.fill", label: "Next Track") {
                    model.skipToNextItem()
                }
            }
        }
        .disabled(model.nowPlaying == nil)
    }

    private var displayedProgress: Double {
        isDragging ? draggedProgress : model.position?.trackProgress ?? 0
    }

    private func controlButton(
        _ systemName: String,
        label: LocalizedStringKey,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(controlFont(prominent: prominent))
                .frame(
                    width: style == .immersive ? 58 : (prominent ? 48 : 38),
                    height: style == .immersive ? 58 : (prominent ? 48 : 38)
                )
                .background {
                    if style == .standard {
                        Circle().fill(prominent ? Color.accentColor : Color.secondary.opacity(0.12))
                    }
                }
                .foregroundStyle(style == .immersive || prominent ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func controlFont(prominent: Bool) -> Font {
        if style == .immersive {
            return .system(size: prominent ? 32 : 23, weight: .semibold)
        }
        return prominent ? .title2 : .body
    }

    private func timeText(progress: Double, durationMs: Int) -> String {
        let totalSeconds = max(0, Int((Double(durationMs) * progress / 1_000).rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
