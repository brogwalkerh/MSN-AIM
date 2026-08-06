import Foundation

/// Brings saved layouts forward across schema changes.
///
/// Shipped at version 1 with nothing to do, which is the point: adding it now costs
/// twenty lines and a fixture, and adding it later — once real users have real layouts
/// on disk written by a build that had no version marker — costs considerably more.
///
/// The rule when adding a version: keep the old shape as a private nested type, write a
/// function that converts it to the current one, add a case below, and commit a fixture
/// of the old format to `Tests/.../Fixtures`. Never edit an existing fixture.
public enum LayoutMigrator {
    public enum MigrationError: Error, Hashable, Sendable {
        /// Written by a newer build. Callers should fall back to a preset rather than
        /// destroying a document they cannot understand.
        case unsupportedFutureVersion(found: Int, supported: Int)
        case malformed(String)
    }

    /// Just enough of the document to find out what shape the rest of it is in.
    private struct VersionProbe: Decodable {
        let schemaVersion: Int?
    }

    public static func migrate(_ data: Data) throws -> LayoutDocument {
        let decoder = LayoutCodec.makeDecoder()

        let version: Int
        do {
            version = try decoder.decode(VersionProbe.self, from: data).schemaVersion ?? 1
        } catch {
            throw MigrationError.malformed("not a layout document: \(error)")
        }

        switch version {
        case ...0:
            throw MigrationError.malformed("schemaVersion \(version) is not a valid version")

        case 1:
            return try decodeV1(data, decoder: decoder)

        default:
            throw MigrationError.unsupportedFutureVersion(
                found: version,
                supported: LayoutDocument.currentSchemaVersion
            )
        }
    }

    private static func decodeV1(_ data: Data, decoder: JSONDecoder) throws -> LayoutDocument {
        do {
            return try decoder.decode(LayoutDocument.self, from: data)
        } catch {
            throw MigrationError.malformed("v1 document did not decode: \(error)")
        }
    }
}
