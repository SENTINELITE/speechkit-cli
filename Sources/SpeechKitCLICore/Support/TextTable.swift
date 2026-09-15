import Foundation

/// Renders fixed-width plain ASCII tables.
///
/// Output carries no colour and no box drawing, so it stays readable when the
/// tool is piped into a file or a pager.
public struct TextTable: Sendable {
    /// The column headings, printed uppercased.
    public let headers: [String]
    /// The rows, each with one entry per heading.
    public let rows: [[String]]
    /// The gap between columns.
    public let gap: Int

    /// Creates a table.
    public init(headers: [String], rows: [[String]], gap: Int = 2) {
        self.headers = headers
        self.rows = rows
        self.gap = gap
    }

    /// Returns the table as text, with a trailing newline on every line.
    ///
    /// Columns are padded to the widest cell. The last column is never padded,
    /// so no line carries trailing spaces.
    public func render() -> String {
        let all = [headers.map { $0.uppercased() }] + rows
        var widths = [Int](repeating: 0, count: headers.count)
        for row in all {
            for (index, cell) in row.enumerated() where index < widths.count {
                widths[index] = max(widths[index], cell.count)
            }
        }

        let separator = String(repeating: " ", count: gap)
        return all.map { row in
            row.enumerated()
                .map { index, cell in
                    index == row.count - 1 ? cell : cell.padding(toLength: widths[index], withPad: " ", startingAt: 0)
                }
                .joined(separator: separator)
                .trimmingTrailingSpaces() + "\n"
        }.joined()
    }
}

extension String {
    /// Returns the string without trailing spaces.
    func trimmingTrailingSpaces() -> String {
        var copy = self
        while copy.hasSuffix(" ") { copy.removeLast() }
        return copy
    }
}
