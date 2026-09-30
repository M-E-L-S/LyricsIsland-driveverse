#if canImport(UIKit)
import UIKit
import Testing
@testable import DriveVerse

@Suite @MainActor struct LiveLyricsFillLayoutTests {
    private func rows(_ text: String, progress: Double,
                      width: CGFloat = 300, height: CGFloat = 60,
                      rightToLeft: Bool = false) -> [LiveLyricsFillRow] {
        LiveLyricsFillLayout.rows(
            text: text,
            size: CGSize(width: width, height: height),
            font: .systemFont(ofSize: 20, weight: .bold),
            minimumScale: 1,
            rightToLeft: rightToLeft,
            progress: progress
        )
    }

    @Test func revealsPartOfAChineseGlyph() throws {
        let start = try #require(rows("你好世界", progress: 0).first)
        let half = try #require(rows("你好世界", progress: 0.5).first)
        let first = try #require(rows("你好世界", progress: 1).first)
        #expect(start.filledWidth == 0)
        #expect(half.filledWidth > 0)
        #expect(half.filledWidth < first.filledWidth)
        #expect(start.bounds == half.bounds)
        #expect(half.bounds == first.bounds)
    }

    @Test func preservesGraphemeBoundaries() throws {
        let text = "👨‍👩‍👧‍👦e\u{301}你"
        #expect(text.count == 3)
        let emoji = try #require(rows(text, progress: 1).first)
        let halfAccent = try #require(rows(text, progress: 1.5).first)
        let accent = try #require(rows(text, progress: 2).first)
        let complete = try #require(rows(text, progress: 3).first)
        #expect(emoji.filledWidth < halfAccent.filledWidth)
        #expect(halfAccent.filledWidth < accent.filledWidth)
        #expect(accent.filledWidth < complete.filledWidth)
        #expect(rows(text, progress: 99).first?.filledWidth == complete.filledWidth)
    }

    @Test func advancesWrappedRowsWithoutChangingTheirBounds() {
        let text = "你好世界你好世界你好世界你好世界"
        let start = rows(text, progress: 0, width: 110)
        let early = rows(text, progress: 1, width: 110)
        let complete = rows(text, progress: Double(text.count), width: 110)
        #expect(start.count == 2)
        #expect(start.map(\.bounds) == early.map(\.bounds))
        #expect(start.map(\.bounds) == complete.map(\.bounds))
        #expect(start.allSatisfy { $0.filledWidth == 0 })
        #expect((early.first?.filledWidth ?? 0) > 0)
        #expect(early.last?.filledWidth == 0)
        #expect(complete.allSatisfy { $0.filledWidth > 0 && $0.filledWidth <= $0.bounds.width })
    }

    @Test func measuresRightToLeftFillFromTheLeadingEdge() throws {
        let text = "שלום"
        let half = try #require(rows(text, progress: 0.5, rightToLeft: true).first)
        let complete = try #require(rows(text, progress: Double(text.count), rightToLeft: true).first)
        #expect(half.filledWidth > 0)
        #expect(half.filledWidth < complete.filledWidth)
    }

    @Test func emptyTextAndZeroSizeHaveNoMaskRows() {
        #expect(rows("", progress: 0).isEmpty)
        #expect(rows("你好", progress: 1, width: 0).isEmpty)
        #expect(rows("你好", progress: 1, height: 0).isEmpty)
    }
}
#endif
