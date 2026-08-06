import Foundation

/// Where saved layouts live.
///
/// A protocol so the layout model can be exercised on Linux against
/// `InMemoryLayoutStore`, while the app writes JSON files. Deliberately synchronous: a
/// handful of small documents, read once at launch and written on edit, is not worth an
/// async surface — and an async store would push `await` through every layout mutation
/// in the UI for no benefit.
public protocol LayoutStore: Sendable {
    func loadAll() throws -> [LayoutDocument]
    func save(_ document: LayoutDocument) throws
    func delete(_ id: UUID) throws

    func loadActiveID() -> UUID?
    func setActiveID(_ id: UUID?)
}

extension LayoutStore {
    /// Loads the library, seeding it from the default preset on first run so the app
    /// never starts with an empty dashboard.
    public func loadOrSeed(now: Date) throws -> (documents: [LayoutDocument], activeID: UUID) {
        var documents = try loadAll()

        if documents.isEmpty {
            let seeded = LayoutPresets.all.map { $0.document(now: now) }
            for document in seeded {
                try save(document)
            }
            documents = seeded
        }

        // Force-unwrapping would be safe here, but a corrupt store that returns an empty
        // array after a successful seed should not crash the app on launch.
        guard let fallback = documents.first else {
            let document = LayoutPresets.default.document(now: now)
            try save(document)
            setActiveID(document.id)
            return ([document], document.id)
        }

        let active = loadActiveID().flatMap { id in
            documents.contains { $0.id == id } ? id : nil
        } ?? fallback.id

        setActiveID(active)
        return (documents, active)
    }
}

/// A store that keeps everything in memory. Used by tests, and by previews.
public final class InMemoryLayoutStore: LayoutStore, @unchecked Sendable {
    private let lock = NSLock()
    private var documents: [UUID: LayoutDocument] = [:]
    private var order: [UUID] = []
    private var activeID: UUID?

    public init(_ seed: [LayoutDocument] = []) {
        for document in seed {
            documents[document.id] = document
            order.append(document.id)
        }
        activeID = seed.first?.id
    }

    public func loadAll() throws -> [LayoutDocument] {
        lock.lock()
        defer { lock.unlock() }
        return order.compactMap { documents[$0] }
    }

    public func save(_ document: LayoutDocument) throws {
        lock.lock()
        defer { lock.unlock() }
        if documents[document.id] == nil {
            order.append(document.id)
        }
        documents[document.id] = document
    }

    public func delete(_ id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        documents[id] = nil
        order.removeAll { $0 == id }
        if activeID == id {
            activeID = order.first
        }
    }

    public func loadActiveID() -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        return activeID
    }

    public func setActiveID(_ id: UUID?) {
        lock.lock()
        defer { lock.unlock() }
        activeID = id
    }
}
