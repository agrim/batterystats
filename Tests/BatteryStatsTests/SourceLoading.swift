import XCTest

extension XCTestCase {
    static func sourceURL(relativePath: String) -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return root.appendingPathComponent(relativePath)
    }

    static func loadSource(relativePath: String) throws -> String {
        try String(contentsOf: sourceURL(relativePath: relativePath), encoding: .utf8)
    }
}
