import Foundation

/// JSON encoding for saved layouts.
///
/// JSON via `Codable` rather than SwiftData, deliberately. A layout document is one
/// small recursive tree, not a queryable object graph; versioned migration of a
/// recursive enum is far easier to reason about — and to write fixtures for — than a
/// SwiftData schema migration; and, decisively here, JSON round-trips inside a Linux
/// unit test where SwiftData does not exist at all.
public enum LayoutCodec {
    /// Sorted keys and pretty printing are not cosmetic: the golden fixture in the test
    /// suite is compared byte for byte, and an unordered encoder would make it fail at
    /// random.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encode(_ document: LayoutDocument) throws -> Data {
        try makeEncoder().encode(document)
    }

    /// Decodes a document, migrating it forward if it was written by an older build.
    public static func decode(_ data: Data) throws -> LayoutDocument {
        try LayoutMigrator.migrate(data)
    }
}
