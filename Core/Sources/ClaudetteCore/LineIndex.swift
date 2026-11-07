import Foundation

/// Converts the parser's line and UTF-8 column positions to UTF-16 offsets.
public struct LineIndex: Sendable {
    private let bytes: [UInt8]
    private var lineStartsUTF8: [Int] = [0]
    private var lineStartsUTF16: [Int] = [0]
    private let totalUTF16: Int

    public init(_ text: String) {
        bytes = Array(text.utf8)
        var utf16 = 0
        var i = 0
        while i < bytes.count {
            let byte = bytes[i]
            let width = Self.width(ofLeadByte: byte)
            utf16 += width == 4 ? 2 : 1
            i += width
            let isLF = byte == 0x0A
            let isLoneCR = byte == 0x0D && (i >= bytes.count || bytes[i] != 0x0A)
            if isLF || isLoneCR {
                lineStartsUTF8.append(i)
                lineStartsUTF16.append(utf16)
            }
        }
        totalUTF16 = utf16
    }

    /// `line` and `utf8Column` are 1-based. Positions past the end clamp to the end.
    public func offset(line: Int, utf8Column: Int) -> Int {
        guard line >= 1, line <= lineStartsUTF8.count else { return totalUTF16 }
        var i = lineStartsUTF8[line - 1]
        let target = min(i + utf8Column - 1, bytes.count)
        var utf16 = lineStartsUTF16[line - 1]
        while i < target {
            let width = Self.width(ofLeadByte: bytes[i])
            utf16 += width == 4 ? 2 : 1
            i += width
        }
        return utf16
    }

    private static func width(ofLeadByte byte: UInt8) -> Int {
        switch byte {
        case 0xF0...: return 4
        case 0xE0...: return 3
        case 0xC0...: return 2
        default: return 1
        }
    }
}
