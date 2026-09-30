#if canImport(UIKit)
import UIKit

/// Samples the actual glyph ink, including wrapping, truncation and RTL layout.
/// Only a bounded set of native Circle views is archived by the widget.
@MainActor
enum LiveLyricsParticleLayout {
    static let maximumParticleCount = 900

    private final class Samples: NSObject {
        let points: [CGPoint]
        init(_ points: [CGPoint]) { self.points = points }
    }

    private static let cache: NSCache<NSString, Samples> = {
        let cache = NSCache<NSString, Samples>()
        cache.countLimit = 12
        return cache
    }()

    static func points(text: String, size: CGSize, font: UIFont,
                       minimumScale: CGFloat, rightToLeft: Bool) -> [CGPoint] {
        guard !text.isEmpty, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0,
              size.width <= 2_048, size.height <= 512 else { return [] }
        let key = "\(text)|\(size.width)|\(size.height)|\(font.fontName)|\(font.pointSize)|\(minimumScale)|\(rightToLeft)" as NSString
        if let samples = cache.object(forKey: key) { return samples.points }

        let full = Measurement(text: text, width: size.width, font: font,
                               rightToLeft: rightToLeft, lineLimit: 0)
        let visibleCount = min(2, full.fragments.count)
        guard visibleCount > 0 else { return [] }
        let fullHeight = full.fragments[visibleCount - 1].bounds.maxY
        let needsScaling = full.fragments.count > 2 || fullHeight > size.height + 1
        let scale = needsScaling
            ? min(1, max(minimumScale, size.height / max(1, fullHeight))) : 1
        let measured = Measurement(text: text, width: size.width,
                                   font: font.withSize(font.pointSize * scale),
                                   rightToLeft: rightToLeft, lineLimit: 2)
        guard !measured.fragments.isEmpty else { return [] }

        let width = Int(ceil(size.width))
        let height = Int(ceil(size.height))
        guard let bitmap = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ), let data = bitmap.data else { return [] }

        // TextKit draws in UIKit's top-left coordinate system.
        bitmap.translateBy(x: 0, y: CGFloat(height))
        bitmap.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(bitmap)
        let rowHeight = size.height / CGFloat(measured.fragments.count)
        for (index, fragment) in measured.fragments.enumerated() {
            measured.manager.drawGlyphs(
                forGlyphRange: fragment.glyphs,
                at: CGPoint(x: 0, y: CGFloat(index) * rowHeight - fragment.bounds.minY)
            )
        }
        UIGraphicsPopContext()

        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var candidates: [CGPoint] = []
        // Column order keeps most morph movement along the reading direction.
        for x in stride(from: 1, to: width, by: 2) {
            for y in stride(from: 1, to: height, by: 2) {
                if pixels[y * bitmap.bytesPerRow + x * 4 + 3] > 96,
                   CGFloat(x) < size.width, CGFloat(y) < size.height {
                    candidates.append(CGPoint(x: x, y: y))
                }
            }
        }
        let count = min(maximumParticleCount, candidates.count)
        let points = (0..<count).map { slot in
            candidates[slot * candidates.count / count]
        }
        cache.setObject(Samples(points), forKey: key)
        return points
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
                .font: font, .foregroundColor: UIColor.white,
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
