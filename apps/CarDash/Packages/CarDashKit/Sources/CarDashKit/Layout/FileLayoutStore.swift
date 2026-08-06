import Foundation
import CarDashCore
import os

/// Saves layouts as one JSON file each under Application Support.
///
/// Application Support rather than Documents: these are the app's own files, not
/// documents the user manages, so they should not appear in the Files app.
public final class FileLayoutStore: LayoutStore, @unchecked Sendable {
    private static let log = Logger(subsystem: "dev.cardash", category: "layout-store")
    private static let activeKey = "cardash.activeLayoutID"

    private let directory: URL
    private let defaults: UserDefaults

    public init(directory: URL? = nil, defaults: UserDefaults = .standard) throws {
        if let directory {
            self.directory = directory
        } else {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.directory = base.appending(path: "CarDash/Layouts", directoryHint: .isDirectory)
        }
        self.defaults = defaults

        try FileManager.default.createDirectory(
            at: self.directory,
            withIntermediateDirectories: true
        )
    }

    public func loadAll() throws -> [LayoutDocument] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }

        // One unreadable file must not take the whole library down with it. A layout
        // written by a newer build, or truncated by a crash mid-write, is skipped and
        // logged; everything else still loads.
        let documents = urls.compactMap { url -> LayoutDocument? in
            do {
                return try LayoutCodec.decode(try Data(contentsOf: url))
            } catch {
                Self.log.error("skipping \(url.lastPathComponent): \(error)")
                return nil
            }
        }

        return documents.sorted { $0.createdAt < $1.createdAt }
    }

    public func save(_ document: LayoutDocument) throws {
        let data = try LayoutCodec.encode(document)
        // Atomic, so a crash or a low-battery shutdown mid-save cannot leave a
        // half-written layout where a whole one used to be.
        try data.write(to: url(for: document.id), options: .atomic)
    }

    public func delete(_ id: UUID) throws {
        let target = url(for: id)
        guard FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) else {
            return
        }
        try FileManager.default.removeItem(at: target)
    }

    public func loadActiveID() -> UUID? {
        defaults.string(forKey: Self.activeKey).flatMap(UUID.init(uuidString:))
    }

    public func setActiveID(_ id: UUID?) {
        if let id {
            defaults.set(id.uuidString, forKey: Self.activeKey)
        } else {
            defaults.removeObject(forKey: Self.activeKey)
        }
    }

    private func url(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }
}
