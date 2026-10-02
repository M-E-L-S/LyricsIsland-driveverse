#if canImport(UIKit)
import UIKit

struct LiveLyricsFillRow {
    let bounds: CGRect
    let filledWidth: CGFloat
}

/// Rectangles cover the entire held token, including any wrapped rows.
struct LiveLyricsTailGeometry {
    let wordBounds: [CGRect]
}

/// Measures mask endpoints at archive time. The visible text is still laid out
/// by SwiftUI; the system animates the resulting native offset modifiers.
@MainActor
enum LiveLyricsFillLayout {
    static func rows(
        text: String,
        size: CGSize,
        font: UIFont,
        minimumScale: CGFloat,
        rightToLeft: Bool,
        progress: Double
    ) -> [LiveLyricsFillRow] {
        guard let measured = measurement(text: text, size: size, font: font,
                                          minimumScale: minimumScale,
                                          rightToLeft: rightToLeft) else { return [] }

        // ContentState uses Swift Character counts, while TextKit indexes UTF-16.
        // Preserve grapheme boundaries for emoji and combining characters.
        var boundaries = [0]
        for character in text {
            boundaries.append(boundaries.last! + String(character).utf16.count)
        }
        let value = min(Double(boundaries.count - 1), max(0, progress))
        let whole = Int(value)
        let fraction = CGFloat(value - Double(whole))
        let completedGlyphs = measured.manager.glyphRange(
            forCharacterRange: NSRange(location: 0, length: boundaries[whole]),
            actualCharacterRange: nil
        )
        let partialGlyphs: NSRange
        if fraction > 0, whole + 1 < boundaries.count {
            partialGlyphs = measured.manager.glyphRange(
                forCharacterRange: NSRange(location: boundaries[whole],
                                          length: boundaries[whole + 1] - boundaries[whole]),
                actualCharacterRange: nil
            )
        } else {
            partialGlyphs = NSRange(location: 0, length: 0)
        }

        let rowHeight = size.height / CGFloat(measured.fragments.count)
        return measured.fragments.enumerated().map { index, fragment in
            let complete = NSIntersectionRange(completedGlyphs, fragment.glyphs)
            var filled: CGFloat = 0
            if complete.length > 0 {
                let rect = measured.manager.boundingRect(forGlyphRange: complete,
                                                        in: measured.container)
                filled = rightToLeft ? size.width - rect.minX : rect.maxX
            }
            let partial = NSIntersectionRange(partialGlyphs, fragment.glyphs)
            if partial.length > 0 {
                let rect = measured.manager.boundingRect(forGlyphRange: partial,
                                                        in: measured.container)
                let edge = rightToLeft
                    ? size.width - rect.maxX + rect.width * fraction
                    : rect.minX + rect.width * fraction
                filled = max(filled, edge)
            }
            return LiveLyricsFillRow(
                bounds: CGRect(x: 0, y: CGFloat(index) * rowHeight,
                               width: size.width, height: rowHeight),
                filledWidth: min(size.width, max(0, filled))
            )
        }
    }

    static func tail(text: String, characterStart: Int, size: CGSize, font: UIFont,
                     minimumScale: CGFloat, rightToLeft: Bool) -> LiveLyricsTailGeometry? {
        guard characterStart >= 0, characterStart < text.count,
              let measured = measurement(text: text, size: size, font: font,
                                         minimumScale: minimumScale, rightToLeft: rightToLeft)
        else { return nil }
        let token = String(text.dropFirst(characterStart))
        let prefix = String(text.prefix(characterStart)).utf16.count
        let range = NSRange(location: prefix, length: token.utf16.count)
        let glyphs = measured.manager.glyphRange(forCharacterRange: range,
                                                 actualCharacterRange: nil)
        let rowHeight = size.height / CGFloat(measured.fragments.count)
        var wordBounds: [CGRect] = []
        for (row, fragment) in measured.fragments.enumerated() {
            let visible = NSIntersectionRange(glyphs, fragment.glyphs)
            guard visible.length > 0 else { continue }
            let rect = measured.manager.boundingRect(forGlyphRange: visible, in: measured.container)
            let left = max(0, rect.minX)
            let right = min(size.width, rect.maxX)
            if right > left {
                wordBounds.append(CGRect(x: left, y: CGFloat(row) * rowHeight,
                                         width: right - left, height: rowHeight))
            }
        }
        guard !wordBounds.isEmpty else { return nil }
        return LiveLyricsTailGeometry(wordBounds: wordBounds)
    }

    private static func measurement(text: String, size: CGSize, font: UIFont,
                                    minimumScale: CGFloat, rightToLeft: Bool) -> Measurement? {
        guard !text.isEmpty, size.width > 0, size.height > 0 else { return nil }

        let fullSize = Measurement(text: text, width: size.width, font: font,
                                   rightToLeft: rightToLeft, lineLimit: 0)
        let visibleLineCount = min(2, fullSize.fragments.count)
        guard visibleLineCount > 0 else { return nil }

        // Estimate Text's font reduction from its actual rendered height,
        // respecting the same two-line limit and minimumScaleFactor.
        let fullHeight = fullSize.fragments[visibleLineCount - 1].bounds.maxY
        let needsScaling = fullSize.fragments.count > 2 || fullHeight > size.height + 1
        let scale = needsScaling
            ? min(1, max(minimumScale, size.height / max(1, fullHeight))) : 1
        let measured = Measurement(text: text, width: size.width,
                                   font: font.withSize(font.pointSize * scale),
                                   rightToLeft: rightToLeft, lineLimit: 2)
        guard !measured.fragments.isEmpty else { return nil }

        return measured
    }

    private struct Fragment {
        let bounds: CGRect
        let glyphs: NSRange
    }

    private final class Measurement {
        let manager = NSLayoutManager()
        let container: NSTextContainer
        let storage: NSTextStorage
        var fragments: [Fragment] = []

        init(text: String, width: CGFloat, font: UIFont,
             rightToLeft: Bool, lineLimit: Int) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = rightToLeft ? .right : .left
            paragraph.baseWritingDirection = rightToLeft ? .rightToLeft : .leftToRight
            storage = NSTextStorage(string: text, attributes: [
                .font: font,
                .paragraphStyle: paragraph
            ])
            container = NSTextContainer(size: CGSize(width: width,
                                                     height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            container.maximumNumberOfLines = lineLimit
            container.lineBreakMode = lineLimit > 0 ? .byTruncatingTail : .byWordWrapping
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            manager.ensureLayout(for: container)
            manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) {
                rect, _, _, glyphs, _ in
                self.fragments.append(Fragment(bounds: rect, glyphs: glyphs))
            }
        }
    }
}
#endif
