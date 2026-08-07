import Foundation

/// The saved favourites, and the rules about what may go in.
///
/// A value type with non-mutating operations, so the Phone and Messages tiles share one list
/// and neither can quietly corrupt it. All of it is pure, which is the point — this is the part
/// of the contacts feature that can be proved on Linux, leaving the picker and the dialler as
/// the only bits that need a device.
public struct FavouritesList: Codable, Hashable, Sendable {
    public private(set) var entries: [Favourite]

    /// A ceiling, not a limit of the storage.
    ///
    /// A tile in a car is glanced at, not browsed. Past about a dozen faces the grid stops
    /// being something you can hit without looking and becomes a list you have to read, which
    /// is the thing this tile exists to avoid.
    public static let capacity = 12

    public init(entries: [Favourite] = []) {
        self.entries = Array(entries.prefix(Self.capacity))
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }
    public var isFull: Bool { entries.count >= Self.capacity }

    public func contains(number: String) -> Bool {
        entries.contains { PhoneNumber.isSameNumber($0.phoneNumber, number) }
    }

    /// Appends, unless the number is already saved or there is no room.
    ///
    /// Adding a duplicate is silently a no-op rather than an error: picking the same person
    /// twice is an ordinary slip, and two identical buttons would be worse than nothing
    /// happening. The name is *not* updated from a duplicate add — an existing favourite the
    /// user has arranged should not be reordered or relabelled by a mistaken tap.
    public func adding(_ favourite: Favourite) -> FavouritesList {
        guard favourite.isDiallable else { return self }
        guard !contains(number: favourite.phoneNumber) else { return self }
        guard !isFull else { return self }
        return FavouritesList(entries: entries + [favourite])
    }

    /// Adds several at once, which is what the contact picker returns.
    ///
    /// Deduplicates within the batch as well as against what is already saved, and stops at
    /// capacity rather than dropping the earlier ones.
    public func adding(contentsOf newcomers: [Favourite]) -> FavouritesList {
        newcomers.reduce(self) { $0.adding($1) }
    }

    public func removing(_ id: Favourite.ID) -> FavouritesList {
        FavouritesList(entries: entries.filter { $0.id != id })
    }

    public func removing(number: String) -> FavouritesList {
        FavouritesList(entries: entries.filter { !PhoneNumber.isSameNumber($0.phoneNumber, number) })
    }

    /// Moves an entry, for drag-to-reorder. Out-of-range indices leave the list untouched
    /// rather than trapping — a gesture that ends somewhere unexpected should do nothing.
    public func moving(from source: Int, to destination: Int) -> FavouritesList {
        guard entries.indices.contains(source) else { return self }
        let clamped = min(max(destination, 0), entries.count - 1)
        guard clamped != source else { return self }

        var moved = entries
        let entry = moved.remove(at: source)
        moved.insert(entry, at: clamped)
        return FavouritesList(entries: moved)
    }

    public func entry(_ id: Favourite.ID) -> Favourite? {
        entries.first { $0.id == id }
    }

    /// The first few, for a tile too small to show them all.
    public func prefix(_ maximum: Int) -> [Favourite] {
        Array(entries.prefix(max(0, maximum)))
    }
}
