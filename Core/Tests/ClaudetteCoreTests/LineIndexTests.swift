import Testing
@testable import ClaudetteCore

@Suite struct LineIndexTests {
    @Test func offsetOnSecondLine() {
        #expect(LineIndex("ab\ncd").offset(line: 2, utf8Column: 2) == 4)
    }

    @Test func offsetHandlesEmojiBeforeColumn() {
        // "😀" is 4 UTF-8 bytes and 2 UTF-16 units.
        #expect(LineIndex("😀x").offset(line: 1, utf8Column: 5) == 2)
    }

    @Test func offsetHandlesCRLF() {
        #expect(LineIndex("ab\r\ncd").offset(line: 2, utf8Column: 1) == 4)
    }

    @Test func offsetAtEndOfFile() {
        #expect(LineIndex("ab").offset(line: 1, utf8Column: 3) == 2)
    }

    @Test func offsetPastLastLineClampsToEnd() {
        #expect(LineIndex("ab\n").offset(line: 9, utf8Column: 1) == 3)
    }
}
